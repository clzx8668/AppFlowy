import 'dart:async';

import 'package:appflowy/extensions/flash_note_entry.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/material.dart';

/// 文档底部的「子页面」区块：把当前页面当作"文件夹"用。
///
/// 为什么需要它：沿用上游"页面即容器、可无限嵌套"的模型后，手机端点进一个页面只能看到
/// 它自己的正文，看不到它的子页面（上游手机端要看子页面得回到侧边抽屉）。
/// 这里在文档底部列出**本页的子页面**并提供「新建子页面」，让手机端也能像文件夹一样上下钻取。
///
/// 挂载点与「反向链接」面板相同：上游 `AppFlowyEditor(footer:)` 插槽，不改编辑器内部实现。
class ChildPagesSection extends StatefulWidget {
  const ChildPagesSection({super.key, required this.pageId});

  /// 当前页面的 view id（文档页的 documentId 即 view id）。
  final String pageId;

  @override
  State<ChildPagesSection> createState() => _ChildPagesSectionState();
}

class _ChildPagesSectionState extends State<ChildPagesSection> {
  List<ViewPB> _children = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final result = await ViewBackendService.getChildViews(
        viewId: widget.pageId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _children = result.toNullable() ?? const <ViewPB>[];
        _loading = false;
      });
    } catch (e) {
      Log.error('[子页面] 加载失败：$e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createChildPage() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final created = await ViewBackendService.createView(
        layoutType: ViewLayoutPB.Document,
        parentViewId: widget.pageId,
        name: '',
      );
      final view = created.toNullable();
      await _reload();
      if (view != null && mounted) {
        await openDocumentByViewId(context, view.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('新建子页面失败：$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.folder_outlined,
                size: 15,
                color: _children.isEmpty
                    ? theme.colorScheme.outline
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '子页面 ${_children.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _busy ? null : () => unawaited(_createChildPage()),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建子页面'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          if (_children.isEmpty)
            Text(
              '这个页面下面还没有子页面；可以用它当文件夹，把相关记录放进来',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            )
          else
            for (final child in _children)
              InkWell(
                onTap: () => unawaited(
                  openDocumentByViewId(context, child.id),
                ),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 14,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          child.name.isEmpty ? '未命名页面' : child.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: theme.colorScheme.outline,
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
