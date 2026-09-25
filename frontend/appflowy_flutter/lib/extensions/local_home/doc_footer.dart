import 'dart:async';

import 'package:appflowy/extensions/kb_links/backlinks_panel.dart';
import 'package:appflowy/extensions/kb_links_entry.dart';
import 'package:appflowy/extensions/local_home/child_pages_section.dart';
import 'package:appflowy/extensions/page_tags.dart';
import 'package:appflowy/extensions/when_entry.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// 文档底部的**一行折叠条**：把「子页面 / 标签 / 双链」三块收进一个入口。
///
/// 折叠时显示 `📁 3 · #2 · 🔗 1 ⌄`，点开才展开三块；再点标题行收起。
/// 这样做是为了把正文还给用户（长文档底部不再堆三块面板）。
class DocFooter extends StatefulWidget {
  const DocFooter({
    super.key,
    required this.pageId,
    this.editorState,
  });

  final String pageId;

  /// 用于"插入时间标记"（写进编辑器，由编辑器统一提交内核）。
  final EditorState? editorState;

  @override
  State<DocFooter> createState() => _DocFooterState();
}

class _DocFooterState extends State<DocFooter> {
  bool _expanded = false;
  int _childCount = 0;
  int _tagCount = 0;
  int _backlinkCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCounts());
  }

  Future<void> _loadCounts() async {
    var children = 0;
    var tags = 0;
    var backlinks = 0;
    try {
      final result = await ViewBackendService.getChildViews(
        viewId: widget.pageId,
      );
      children = (result.toNullable() ?? const []).length;
      tags = (await loadPageTags(widget.pageId)).length;
      final service = await createLinkService();
      backlinks = (await service.backlinksOf(widget.pageId)).length;
      // 顺便刷新本篇的「时间标记」索引（内容时间 → 日历归类）
      final marks = await collectWhenMarksOfDocument(widget.pageId);
      await saveWhenMarks(widget.pageId, marks);
    } catch (e) {
      Log.error('[文档底部] 统计失败：$e');
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _childCount = children;
      _tagCount = tags;
      _backlinkCount = backlinks;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text(
                    '📁 $_childCount   #$_tagCount   🔗 $_backlinkCount',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (widget.editorState != null)
                    TextButton.icon(
                      onPressed: () =>
                          unawaited(insertWhenMark(widget.editorState!)),
                      icon: const Icon(Icons.schedule, size: 16),
                      label: const Text('时间标记'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            ChildPagesSection(pageId: widget.pageId),
            PageTagsSection(pageId: widget.pageId),
            BacklinksPanel(
              documentId: widget.pageId,
              documentTitle: '',
              editorState: widget.editorState,
            ),
          ],
        ],
      ),
    );
  }
}
