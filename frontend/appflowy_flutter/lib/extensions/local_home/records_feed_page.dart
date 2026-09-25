import 'dart:async';

import 'package:app_containers/app_containers.dart';
import 'package:appflowy/extensions/adapters/container_repository_impl.dart';
import 'package:appflowy/extensions/flash_note_entry.dart';
import 'package:appflowy/extensions/local_home/mobile_ui_kit.dart';
import 'package:appflowy/extensions/page_tags.dart';
import 'package:appflowy/extensions/timeline_entry.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';

/// 一条"记录"（跨分类聚合后的一行）。
class FeedRecord {
  const FeedRecord({
    required this.view,
    required this.kind,
    required this.kindIcon,
  });

  final ViewPB view;
  final String kind;
  final IconData kindIcon;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(
        (view.lastEdited == Int64.ZERO ? view.createTime : view.lastEdited)
                .toInt() *
            1000,
      );

  String get title {
    final name = view.name.trim();
    return name.isEmpty ? '未命名页面' : name;
  }

  List<String> get tags => tagsOfView(view);
}

/// 手机端首页：**全部记录流**（跨分类、按时间倒序）+ 分类/标签筛选。
///
/// 设计对齐 `E:\Dev\moodiaryCRM` 的手机端：卡片式列表、chip 筛选、点击进入、一步新建。
/// 这一层是"呈现"，数据仍是内核页面树（分类容器/子页面只是筛选项），没有新增任何数据模型。
class RecordsFeedPage extends StatefulWidget {
  const RecordsFeedPage({
    super.key,
    required this.repository,
    this.onOpenDrawer,
    this.onOpenSearch,
  });

  final ContainerRepositoryImpl repository;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onOpenSearch;

  @override
  State<RecordsFeedPage> createState() => RecordsFeedPageState();
}

class RecordsFeedPageState extends State<RecordsFeedPage> {
  List<FeedRecord> _all = const [];
  bool _loading = true;

  /// 当前筛选：分类（容器/子页面名）与标签
  String _kindFilter = '';
  final Set<String> _tagFilter = {};

  /// 新建落点：当前筛选对应的父页面 id（"全部"时为空 → 用默认容器）
  String _defaultContainerId = '';

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  /// 供外部（新建后/从详情页返回）刷新。
  Future<void> reload() async {
    try {
      final result = await ViewBackendService.getAllViews();
      final views = result.toNullable()?.items ?? const <ViewPB>[];
      final containers = await widget.repository.listContainers();
      final containerIds = {for (final c in containers) c.viewId};
      final byId = {for (final view in views) view.id: view};

      // 分类容器本身不进流；它们的**子页面**是流的主力
      final records = <FeedRecord>[];
      for (final view in views) {
        if (containerIds.contains(view.id)) {
          continue;
        }
        if (view.layout != ViewLayoutPB.Document) {
          continue;
        }
        // "分类壳"（笔记下的 闪念/工作记录/生活日记）是归档节点，不是具体记录
        if (_isShellPage(view, byId, containerIds)) {
          continue;
        }
        final (kind, icon) = _classify(view, byId, containers);
        records.add(FeedRecord(view: view, kind: kind, kindIcon: icon));
      }
      records.sort((a, b) => b.time.compareTo(a.time));

      final defaultContainer = containers.firstWhere(
        (c) => c.module == ContainerModule.note,
        orElse: () => containers.isEmpty
            ? const ModuleContainer(viewId: '', name: '', module: '')
            : containers.first,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _all = records;
        _defaultContainerId = defaultContainer.viewId;
        _loading = false;
      });
    } catch (e) {
      Log.error('[记录流] 加载失败：$e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// 记录归类：优先看父页面名（闪念/工作记录/生活日记），否则看父容器模块。
  (String, IconData) _classify(
    ViewPB view,
    Map<String, ViewPB> byId,
    List<ModuleContainer> containers,
  ) {
    final parent = byId[view.parentViewId];
    final parentName = parent?.name ?? '';
    switch (parentName) {
      case '闪念':
        return ('闪念', Icons.bolt);
      case '工作记录':
        return ('工作记录', Icons.work_outline);
      case '生活日记':
        return ('日记', Icons.menu_book_outlined);
    }
    for (final container in containers) {
      if (container.viewId == view.parentViewId) {
        switch (container.module) {
          case ContainerModule.diary:
            return ('日记', Icons.menu_book_outlined);
          case ContainerModule.crm:
            return ('CRM', Icons.people_outline);
          case ContainerModule.ai:
            return ('AI 交流', Icons.auto_awesome_outlined);
          case ContainerModule.note:
            return ('笔记', Icons.description_outlined);
          default:
            return (container.name.isEmpty ? '其他' : container.name,
                Icons.folder_outlined);
        }
      }
    }
    return ('笔记', Icons.description_outlined);
  }

  /// 是否是"分类壳"页面：直接挂在分类容器下的默认子页面（闪念/工作记录/生活日记）。
  bool _isShellPage(
    ViewPB view,
    Map<String, ViewPB> byId,
    Set<String> containerIds,
  ) {
    if (!containerIds.contains(view.parentViewId)) {
      return false;
    }
    const shellNames = {'闪念', '工作记录', '生活日记'};
    return shellNames.contains(view.name.trim());
  }

  List<FeedRecord> get _visible {
    return _all.where((record) {
      if (_kindFilter.isNotEmpty && record.kind != _kindFilter) {
        return false;
      }
      if (_tagFilter.isNotEmpty && !_tagFilter.every(record.tags.contains)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  List<String> get _kinds {
    final kinds = <String>[];
    for (final record in _all) {
      if (!kinds.contains(record.kind)) {
        kinds.add(record.kind);
      }
    }
    return kinds;
  }

  List<String> get _allTags {
    final tags = <String>[];
    for (final record in _all) {
      for (final tag in record.tags) {
        if (!tags.contains(tag)) {
          tags.add(tag);
        }
      }
    }
    tags.sort();
    return tags;
  }

  /// 新建落点：选了某个分类 → 该分类的父页面；否则用默认容器。
  ({String id, String kind}) get newRecordTarget {
    if (_kindFilter.isEmpty) {
      return (id: _defaultContainerId, kind: TimelineKind.note);
    }
    // 找到该分类对应的父页面（闪念/工作记录/生活日记 优先）
    for (final record in _all) {
      if (record.kind == _kindFilter) {
        return (id: record.view.parentViewId, kind: _kindFilter);
      }
    }
    return (id: _defaultContainerId, kind: _kindFilter);
  }

  Future<void> _openFilterSheet() async {
    final tags = _allTags;
    final selected = {..._tagFilter};
    final applied = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '按标签筛选',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (tags.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      '还没有标签：在任意页面底部「标签」处添加',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final tag in tags)
                          CheckboxListTile(
                            dense: true,
                            value: selected.contains(tag),
                            title: Text('#$tag'),
                            controlAffinity:
                                ListTileControlAffinity.leading,
                            onChanged: (value) => setSheetState(() {
                              if (value == true) {
                                selected.add(tag);
                              } else {
                                selected.remove(tag);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        selected.clear();
                        setSheetState(() {});
                      },
                      child: const Text('清除'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(sheetContext).pop(true);
                      },
                      child: const Text('应用'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied == true && mounted) {
      setState(() {
        _tagFilter
          ..clear()
          ..addAll(selected);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: widget.onOpenDrawer,
        ),
        title: const Text('记录'),
        actions: [
          if (widget.onOpenSearch != null)
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: widget.onOpenSearch,
            ),
          IconButton(
            tooltip: '筛选',
            icon: Icon(
              _tagFilter.isEmpty ? Icons.filter_alt_outlined : Icons.filter_alt,
            ),
            onPressed: () => unawaited(_openFilterSheet()),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : Column(
              children: [
                // 分类 chips（横滑）：点一下=筛选，不再"进层级"
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      MobFilterChip(
                        label: '全部',
                        selected: _kindFilter.isEmpty,
                        onTap: () => setState(() {
                          _kindFilter = '';
                          _tagFilter.clear();
                        }),
                      ),
                      for (final kind in _kinds)
                        MobFilterChip(
                          label: kind,
                          selected: _kindFilter == kind,
                          onTap: () => setState(() => _kindFilter = kind),
                        ),
                      if (_allTags.isNotEmpty)
                        MobFilterChip(
                          label: _tagFilter.isEmpty
                              ? '标签'
                              : '标签 ${_tagFilter.length}',
                          leading: '#',
                          selected: _tagFilter.isNotEmpty,
                          onTap: () => unawaited(_openFilterSheet()),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? _emptyState(theme)
                      : RefreshIndicator(
                          onRefresh: reload,
                          child: ListView.separated(
                            padding: Mob.pagePadding,
                            itemCount: visible.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) =>
                                _recordCard(theme, visible[index]),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: 12),
          Text(
            _all.isEmpty ? '还没有记录，点右下角新建' : '这个筛选下暂时没有内容',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordCard(ThemeData theme, FeedRecord record) {
    return MobCard(
      onTap: () => unawaited(_open(record)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              record.kindIcon,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      _formatTime(record.time),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      record.kind,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (record.tags.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          record.tags.map((t) => '#$t').join(' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final sameDay = time.year == now.year &&
        time.month == now.month &&
        time.day == now.day;
    if (sameDay) {
      return '今天 ${two(time.hour)}:${two(time.minute)}';
    }
    if (time.year == now.year) {
      return '${two(time.month)}-${two(time.day)} '
          '${two(time.hour)}:${two(time.minute)}';
    }
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }

  Future<void> _open(FeedRecord record) async {
    await openDocumentByViewId(context, record.view.id);
    await reload();
  }
}
