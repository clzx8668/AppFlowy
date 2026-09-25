import 'dart:async';

import 'package:app_containers/app_containers.dart';
import 'package:appflowy/extensions/adapters/container_repository_impl.dart';
import 'package:appflowy/extensions/flash_note_entry.dart';
import 'package:appflowy/extensions/local_home/mobile_ui_kit.dart';
import 'package:appflowy/extensions/local_home/mob_sliding_tabs.dart';
import 'package:appflowy/extensions/local_home/mob_prefs.dart';
import 'package:appflowy/extensions/page_tags.dart';
import 'package:appflowy/extensions/timeline_entry.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
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

  /// 创建时间（默认排序用它 —— 只看不改内容就不会因为"打开过"而换位置）。
  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(
        (view.createTime == Int64.ZERO ? view.lastEdited : view.createTime)
                .toInt() *
            1000,
      );

  String get title {
    final name = view.name.trim();
    return name.isEmpty ? '未命名页面' : name;
  }

  List<String> get tags => tagsOfView(view);
}

/// 记录流的排序方式。
enum FeedSort {
  createdDesc('创建时间 ↓'),
  createdAsc('创建时间 ↑'),
  editedDesc('编辑时间 ↓'),
  titleAsc('标题 A→Z');

  const FeedSort(this.label);
  final String label;
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

class RecordsFeedPageState extends State<RecordsFeedPage>
    with TickerProviderStateMixin {
  /// 主标题行下面那行浅色小字：条数 / 搜索范围摘要（参照 moodiaryCRM 首页标题行）。
  String _titleSubtitle() {
    final count = _all.length;
    if (_query.isNotEmpty) {
      return '搜索「$_query」 · $count 条';
    }
    if (count == 0) {
      return '还没有内容';
    }
    return '共 $count 条';
  }

  /// 记录全集。**必须是可增长的列表**：`_applySort` 会就地排序，
  /// 之前用 `const []` 初始化导致启动时排序抛
  /// 「Unsupported operation: Cannot modify an unmodifiable list」。
  List<FeedRecord> _all = [];
  bool _loading = true;

  /// 顶部标签：用显式 TabController 才能在"滑动切页"后知道当前是哪个分类
  /// （FAB 新建时要按当前分类决定落点）。
  TabController? _tabController;
  List<String> _tabsCache = const ['全部'];
  int _currentTabIndex = 0;

  /// 当前筛选：标签（分类改由顶部标签页承担）
  final Set<String> _tagFilter = {};

  /// 视图形态：列表 / 网格（对齐参考项目的两种卡片）
  bool _gridMode = false;

  /// 排序方式：默认**按创建时间倒序**（打开/关闭页面不会改变排序位置）
  FeedSort _sort = FeedSort.createdDesc;

  /// 搜索态：点顶栏搜索后进入
  bool _searching = false;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  /// 摘要缓存（页面 id → 正文前若干字），列表卡片用它做预览
  final Map<String, String> _summaries = {};
  bool _prefetching = false;

  /// 新建落点：当前筛选对应的父页面 id（"全部"时为空 → 用默认容器）
  String _defaultContainerId = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadPrefs());
    unawaited(reload());
  }

  /// 恢复上次的排序与视图（默认：创建时间 ↓ + 列表）。
  Future<void> _loadPrefs() async {
    final sortIndex = await MobPrefs.readSortIndex();
    final grid = await MobPrefs.readGridMode();
    if (!mounted) {
      return;
    }
    setState(() {
      if (sortIndex != null &&
          sortIndex >= 0 &&
          sortIndex < FeedSort.values.length) {
        _sort = FeedSort.values[sortIndex];
      }
      if (grid != null) {
        _gridMode = grid;
      }
      _applySort(_all);
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
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
      _applySort(records);

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
        _all = List<FeedRecord>.of(records);
        _defaultContainerId = defaultContainer.viewId;
        _loading = false;
      });
      _syncTabController();
      unawaited(_prefetchSummaries());
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
            return (
              container.name.isEmpty ? '其他' : container.name,
              Icons.folder_outlined
            );
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
      if (_query.isNotEmpty) {
        final needle = _query.toLowerCase();
        final haystack = [
          record.title,
          record.kind,
          _summaries[record.view.id] ?? '',
          record.tags.join(' '),
        ].join(' ').toLowerCase();
        if (!haystack.contains(needle)) {
          return false;
        }
      }
      if (_tagFilter.isNotEmpty && !_tagFilter.every(record.tags.contains)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  /// 标签集合：第 0 个是「全部」，其余是各分类。
  List<String> get _tabs => ['全部', ..._kinds];

  /// 数据变化后同步 TabController（分类集合变了就重建）。
  void _syncTabController() {
    final tabs = _tabs;
    if (_tabController != null && _tabsCache.join('|') == tabs.join('|')) {
      return;
    }
    final previousIndex = _currentTabIndex;
    _tabController?.dispose();
    _tabsCache = tabs;
    final controller = TabController(
      length: tabs.length,
      vsync: this,
      initialIndex: previousIndex.clamp(0, tabs.length - 1),
    );
    controller.addListener(() {
      if (controller.index != _currentTabIndex && mounted) {
        setState(() => _currentTabIndex = controller.index);
      }
    });
    _tabController = controller;
    _currentTabIndex = controller.index;
  }

  /// 某个标签下的记录（下标 0 = 全部；其余按分类过滤；标签筛选对所有标签生效）。
  List<FeedRecord> _recordsForTab(int tabIndex) {
    if (tabIndex >= _tabsCache.length) {
      return const [];
    }
    final kind = tabIndex == 0 ? '' : _tabsCache[tabIndex];
    return _visible
        .where((record) => kind.isEmpty || record.kind == kind)
        .toList();
  }

  void _applySort(List<FeedRecord> records) {
    switch (_sort) {
      case FeedSort.createdDesc:
        records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case FeedSort.createdAsc:
        records.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case FeedSort.editedDesc:
        records.sort((a, b) => b.time.compareTo(a.time));
      case FeedSort.titleAsc:
        records.sort((a, b) => a.title.compareTo(b.title));
    }
  }

  /// 切换排序：只重排内存里的列表，不重新拉数据。
  void _setSort(FeedSort sort) {
    setState(() {
      _sort = sort;
      _applySort(_all);
    });
    unawaited(MobPrefs.writeSortIndex(sort.index));
  }

  /// 懒加载正文摘要：每次最多并发 3 篇、每轮最多 40 篇，避免一次性读爆内核。
  Future<void> _prefetchSummaries() async {
    if (_prefetching) {
      return;
    }
    _prefetching = true;
    try {
      var fetched = 0;
      for (var i = 0; i < _all.length && fetched < 40; i += 3) {
        final batch = _all.skip(i).take(3).toList();
        final pending = batch
            .where((record) => !_summaries.containsKey(record.view.id))
            .toList();
        if (pending.isEmpty) {
          continue;
        }
        await Future.wait(
          pending.map((record) async {
            final text = await _summaryOfDocument(record.view.id);
            if (text.isNotEmpty) {
              _summaries[record.view.id] = text;
            } else {
              _summaries[record.view.id] = '';
            }
          }),
        );
        fetched += pending.length;
        if (mounted) {
          setState(() {});
        }
      }
    } finally {
      _prefetching = false;
    }
  }

  /// 读一篇文档的正文前 80 字（失败返回空串）。
  Future<String> _summaryOfDocument(String documentId) async {
    try {
      final result =
          await DocumentService().getDocument(documentId: documentId);
      final document = result.fold((s) => s.toDocument(), (f) => null);
      if (document == null) {
        return '';
      }
      final buffer = StringBuffer();
      for (final node in NodeIterator(
        document: document,
        startNode: document.root,
      ).toList()) {
        final delta = node.delta;
        if (delta == null || delta.isEmpty) {
          continue;
        }
        buffer.write(delta.toPlainText().replaceAll('\n', ' '));
        if (buffer.length >= 80) {
          break;
        }
      }
      final text = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.length <= 80) {
        return text;
      }
      return '${text.substring(0, 80)}…';
    } catch (_) {
      return '';
    }
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
    final kind = _currentTabIndex == 0 ? '' : _tabsCache[_currentTabIndex];
    if (kind.isEmpty) {
      return (id: _defaultContainerId, kind: TimelineKind.note);
    }
    // 找到该分类对应的父页面（闪念/工作记录/生活日记 优先）
    for (final record in _all) {
      if (record.kind == kind) {
        return (id: record.view.parentViewId, kind: kind);
      }
    }
    return (id: _defaultContainerId, kind: kind);
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
                            controlAffinity: ListTileControlAffinity.leading,
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

  /// 「更多」弹层：排序 / 视图 / 标签筛选（默认排序=创建时间，不做多余操作时不用打开它）。
  Future<void> _openMoreSheet() async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '排序',
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
              ),
              for (final option in FeedSort.values)
                RadioListTile<FeedSort>(
                  dense: true,
                  value: option,
                  groupValue: _sort,
                  title: Text(option.label),
                  onChanged: (value) {
                    if (value != null) {
                      _setSort(value);
                      setSheetState(() {});
                    }
                  },
                ),
              const Divider(height: 8),
              ListTile(
                dense: true,
                leading: Icon(
                  _gridMode ? Icons.view_list_outlined : Icons.grid_view,
                ),
                title: Text(_gridMode ? '切换为列表视图' : '切换为网格视图'),
                onTap: () {
                  setState(() => _gridMode = !_gridMode);
                  unawaited(MobPrefs.writeGridMode(_gridMode));
                  Navigator.of(sheetContext).pop();
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.filter_alt_outlined),
                title: Text(
                  _tagFilter.isEmpty
                      ? '按标签筛选'
                      : '按标签筛选（已选 ${_tagFilter.length}）',
                ),
                trailing: _tagFilter.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          setState(() => _tagFilter.clear());
                          Navigator.of(sheetContext).pop();
                        },
                      ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_openFilterSheet());
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Text(
                  '默认按创建时间排序：打开/编辑内容不会改变记录的位置',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        // 手机（底栏外壳）里是"打开抽屉"；桌面端在内容区打开时没有抽屉，
        // 这时交给系统自动生成返回箭头（内容区自带 Navigator）。
        leading: widget.onOpenDrawer == null
            ? null
            : IconButton(
                icon: const Icon(Icons.menu),
                onPressed: widget.onOpenDrawer,
              ),
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索标题 / 正文 / 标签',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              )
            // 主标题行参照 moodiaryCRM 首页「通栏固定标题行」：
            // 两行文字（大标题 + 一行浅色小字）＋ 右侧动作，高度紧凑。
            : MobTitleRow(
                icon: Icons.article_outlined,
                title: '记录',
                subtitle: _titleSubtitle(),
              ),
        actions: [
          if (_searching)
            IconButton(
              tooltip: '退出搜索',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _searching = false;
                _query = '';
                _searchController.clear();
              }),
            )
          else
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: () {
                if (widget.onOpenSearch != null) {
                  widget.onOpenSearch!();
                } else {
                  setState(() => _searching = true);
                }
              },
            ),
          // 三个按钮收成一个「更多」：排序 / 筛选 / 视图
          IconButton(
            tooltip: '更多',
            icon: Icon(
              Icons.more_vert,
              color: _tagFilter.isEmpty && _sort == FeedSort.createdDesc
                  ? null
                  : theme.colorScheme.primary,
            ),
            onPressed: () => unawaited(_openMoreSheet()),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          // 线性滑动标签：下划线指示器跟着滑动，并且可以左右滑动切页
          : Column(
              children: [
                _corpusTabBar(theme),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      for (var i = 0; i < _tabsCache.length; i++)
                        _tabBody(theme, i),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// 顶部分类标签（线性 + 下划线指示器，可横滑、可左右滑动切页）。
  Widget _corpusTabBar(ThemeData theme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      // 自绘左对齐标签（Material 3 的滚动型 TabBar 会带起始偏移，看起来像居中）
      child: _tabController == null
          ? const SizedBox(height: 44)
          : MobSlidingTabs(
              controller: _tabController!,
              labels: [
                for (var i = 0; i < _tabsCache.length; i++)
                  i == 0 ? '全部 ${_all.length}' : _tabsCache[i],
              ],
            ),
    );
  }

  Widget _tabBody(ThemeData theme, int tabIndex) {
    final records = _recordsForTab(tabIndex);
    if (records.isEmpty) {
      return _emptyState(theme);
    }
    return RefreshIndicator(
      onRefresh: reload,
      child: _gridMode
          ? GridView.builder(
              padding: Mob.pagePadding,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.05,
              ),
              itemCount: records.length,
              itemBuilder: (context, index) =>
                  _recordGridCard(theme, records[index]),
            )
          : ListView.separated(
              padding: Mob.pagePadding,
              itemCount: records.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _recordCard(theme, records[index]),
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
      onLongPress: () => unawaited(_showRecordActions(record)),
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
                // 正文预览（懒加载摘要；还没取到就留空，不占位）
                if ((_summaries[record.view.id] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _summaries[record.view.id]!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
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

  /// 网格卡片：对齐参考项目的 `GirdDiaryCardComponent`
  /// （圆角卡片 + 左侧内容 + 底部"时间 + 类型"一行）。
  Widget _recordGridCard(ThemeData theme, FeedRecord record) {
    return MobCard(
      onTap: () => unawaited(_open(record)),
      onLongPress: () => unawaited(_showRecordActions(record)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                record.kindIcon,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  record.kind,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              record.title,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          if ((_summaries[record.view.id] ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _summaries[record.view.id]!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            _formatTime(record.time),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (record.tags.isNotEmpty)
            Text(
              record.tags.take(3).map((t) => '#$t').join('  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final sameDay =
        time.year == now.year && time.month == now.month && time.day == now.day;
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

  // ------------------------------------------------------------ 长按操作

  /// 长按卡片：重命名 / 移动到 / 打标签 / 删除（删除进回收站，可从设置里恢复）。
  Future<void> _showRecordActions(FeedRecord record) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_renameRecord(record));
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: const Text('移动到…'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_moveRecord(record));
              },
            ),
            ListTile(
              leading: const Icon(Icons.sell_outlined),
              title: Text(
                record.tags.isEmpty
                    ? '打标签'
                    : '打标签（当前 ${record.tags.map((t) => '#$t').join(' ')}）',
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_editTags(record));
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                '删除',
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_deleteRecord(record));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _renameRecord(FeedRecord record) async {
    final controller = TextEditingController(text: record.view.name);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '页面标题'),
          onSubmitted: (text) => Navigator.of(dialogContext).pop(text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null) {
      return;
    }
    await ViewBackendService.updateView(
      viewId: record.view.id,
      name: value.trim(),
    );
    await reload();
  }

  /// 移动：列出所有分类容器与它们的子页面作为可选目标（沿用内核 moveViewV2）。
  Future<void> _moveRecord(FeedRecord record) async {
    final containers = await widget.repository.listContainers();
    final result = await ViewBackendService.getAllViews();
    final views = result.toNullable()?.items ?? const <ViewPB>[];
    final targets = <({String id, String label})>[];
    for (final container in containers) {
      targets.add((id: container.viewId, label: container.name));
      for (final view in views) {
        if (view.parentViewId == container.viewId &&
            view.id != record.view.id &&
            view.layout == ViewLayoutPB.Document) {
          targets.add((id: view.id, label: '${container.name} / ${view.name}'));
        }
      }
    }
    if (!mounted) {
      return;
    }
    final target = await showModalBottomSheet<({String id, String label})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '移动到',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final item in targets)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(item.label),
                        onTap: () => Navigator.of(sheetContext).pop(item),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (target == null) {
      return;
    }
    await ViewBackendService.moveViewV2(
      viewId: record.view.id,
      newParentId: target.id,
      prevViewId: null,
      fromSection: ViewSectionPB.Public,
      toSection: ViewSectionPB.Public,
    );
    await reload();
  }

  Future<void> _editTags(FeedRecord record) async {
    final controller = TextEditingController(text: record.tags.join(' '));
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '空格分隔，例如：重要 待跟进',
          ),
          onSubmitted: (text) => Navigator.of(dialogContext).pop(text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null) {
      return;
    }
    await savePageTags(
      record.view.id,
      value.split(RegExp(r'[\s,，]+')).where((t) => t.isNotEmpty).toList(),
    );
    await reload();
  }

  Future<void> _deleteRecord(FeedRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: Text('「${record.title}」会进入回收站，之后可以在设置里恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ViewBackendService.deleteView(viewId: record.view.id);
    await reload();
  }
}
