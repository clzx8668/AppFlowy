import 'dart:async';

import 'package:app_kb_links/app_kb_links.dart';
import 'package:appflowy/extensions/flash_note_entry.dart';
import 'package:appflowy/extensions/kb_links_entry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_block.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// 文档底部的「双链」面板：反向链接（谁引用了我）+ 出链（我引用了谁）。
///
/// 交互（iOS 风格、默认不打扰）：
/// - 有链接时显示一行摘要头（`🔗 反向链接 3 · 出链 1`），点开后展开列表；
/// - 没有任何链接时只留一行浅色提示，教用户用 `@` 建立双链；
/// - 点列表项直接跳到对应页面。
///
/// 索引策略：面板出现时刷新**本篇**的出链（读一篇文档），编辑停止 2 秒后再刷一次，
/// 因此日常使用中索引始终是新的，不需要全库扫描。
class BacklinksPanel extends StatefulWidget {
  const BacklinksPanel({
    super.key,
    required this.documentId,
    required this.documentTitle,
    this.editorState,
  });

  final String documentId;
  final String documentTitle;

  /// 传入后会在编辑停止时自动刷新索引与反链。
  final EditorState? editorState;

  @override
  State<BacklinksPanel> createState() => _BacklinksPanelState();
}

class _BacklinksPanelState extends State<BacklinksPanel> {
  LinkService? _service;
  List<DocLink> _backlinks = const [];
  List<DocLink> _outgoing = const [];
  List<UnlinkedMention> _suggestions = const [];
  bool _loading = true;
  bool _expanded = false;
  Timer? _debounce;
  StreamSubscription<EditorTransactionValue>? _subscription;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
    _subscription = widget.editorState?.transactionStream.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), () => unawaited(_reload()));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _service = await createLinkService();
    } catch (e) {
      Log.error('[双链] 初始化失败：$e');
    }
    await _reload();
  }

  Future<void> _reload() async {
    final service = _service;
    if (service == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }
    try {
      final titles = await loadViewTitles();
      await indexDocumentLinks(
        service: service,
        documentId: widget.documentId,
        title: widget.documentTitle,
        titles: titles,
      );
      final backlinks = await service.backlinksOf(widget.documentId);
      final outgoing = await service.outgoingOf(widget.documentId);
      final suggestions = await _findSuggestions(titles);
      if (!mounted) {
        return;
      }
      setState(() {
        _backlinks = backlinks;
        _outgoing = outgoing;
        _suggestions = suggestions;
        _loading = false;
      });
    } catch (e) {
      Log.error('[双链] 刷新失败：$e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// 找"未链接提及"：正文里写了别的页面名，但还没做引用（一键建立双链）。
  Future<List<UnlinkedMention>> _findSuggestions(
    Map<String, String> titles,
  ) async {
    final editorState = widget.editorState;
    if (editorState == null || titles.isEmpty) {
      return const [];
    }
    try {
      return findUnlinkedMentions(
        document: editorState.document,
        sourceId: widget.documentId,
        titles: titles,
      );
    } catch (e) {
      Log.error('[双链] 查找未链接提及失败：$e');
      return const [];
    }
  }

  /// 把正文里的纯文本标题变成真实引用（写进编辑器，由编辑器统一提交内核）。
  Future<void> _linkMention(UnlinkedMention suggestion) async {
    final editorState = widget.editorState;
    if (editorState == null) {
      return;
    }
    final transaction = editorState.transaction
      ..formatText(
        suggestion.node,
        suggestion.start,
        suggestion.length,
        MentionBlockKeys.buildMentionPageAttributes(
          mentionType: MentionType.page,
          pageId: suggestion.targetId,
          blockId: null,
        ),
      );
    await editorState.apply(transaction);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const SizedBox.shrink();
    }
    final hasLinks = _backlinks.isNotEmpty ||
        _outgoing.isNotEmpty ||
        _suggestions.isNotEmpty;

    if (!hasLinks) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          children: [
            Icon(Icons.link, size: 14, color: theme.colorScheme.outline),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '还没有双链：在正文里用 @ 提及其他页面，即可在此看到反向链接',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
                  Icon(
                    Icons.link,
                    size: 15,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '反向链接 ${_backlinks.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_outgoing.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Text(
                      '出链 ${_outgoing.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                  const Spacer(),
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
            if (_backlinks.isNotEmpty) ...[
              _sectionTitle(theme, '引用本页'),
              for (final link in _backlinks)
                _linkTile(theme, link, isBacklink: true),
            ],
            if (_outgoing.isNotEmpty) ...[
              const SizedBox(height: 4),
              _sectionTitle(theme, '本页引用'),
              for (final link in _outgoing)
                _linkTile(theme, link, isBacklink: false),
            ],
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 4),
              _sectionTitle(theme, '可以链接（正文提到但还没引用）'),
              for (final suggestion in _suggestions)
                _suggestionTile(theme, suggestion),
            ],
          ],
        ],
      ),
    );
  }

  Widget _suggestionTile(ThemeData theme, UnlinkedMention suggestion) {
    return InkWell(
      onTap: () => unawaited(_linkMention(suggestion)),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Icon(
              Icons.add_link,
              size: 14,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                suggestion.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Text(
              '建立引用',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }

  Widget _linkTile(ThemeData theme, DocLink link, {required bool isBacklink}) {
    final title = isBacklink
        ? (link.sourceTitle.isEmpty ? '未命名页面' : link.sourceTitle)
        : (link.targetTitle.isEmpty ? '未命名页面' : link.targetTitle);
    final id = isBacklink ? link.sourceId : link.targetId;
    return InkWell(
      onTap: () => unawaited(openDocumentByViewId(context, id)),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Icon(
                link.isBlockRef
                    ? Icons.widgets_outlined
                    : Icons.description_outlined,
                size: 14,
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (link.context.isNotEmpty)
                    Text(
                      link.context,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
