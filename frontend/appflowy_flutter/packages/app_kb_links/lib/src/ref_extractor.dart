import 'page_ref.dart';

/// 内联属性键（与上游 `MentionBlockKeys` 保持一致，但这里不依赖编辑器包，
/// 因此写成常量，扩展包保持"零内核依赖"）。
const String kMentionAttributeKey = 'mention';
const String kMentionTypeKey = 'type';
const String kMentionPageIdKey = 'page_id';
const String kMentionBlockIdKey = 'block_id';

/// 从一段 **delta JSON**（`Delta.toJson()` 的结果）里抽出页面引用。
///
/// delta 是 AppFlowy 编辑器的行内格式：`[{insert: '文字', attributes: {...}}, ...]`，
/// 其中页面提及会带 `attributes.mention = {type: 'page', page_id, block_id?}`。
/// 纯函数、无副作用，可单测/脚本验证（见 `doc/tools/kb_links_probe.dart`）。
List<PageRef> extractPageRefsFromDelta({
  required String sourceId,
  required String blockId,
  required List<dynamic> deltaJson,
  String context = '',
  int contextLength = 80,
}) {
  final refs = <PageRef>[];
  final seen = <String>{};
  final snippet = context.length <= contextLength
      ? context
      : '${context.substring(0, contextLength)}…';

  for (final op in deltaJson) {
    if (op is! Map) {
      continue;
    }
    final attributes = op['attributes'];
    if (attributes is! Map) {
      continue;
    }
    final mention = attributes[kMentionAttributeKey];
    if (mention is! Map) {
      continue;
    }
    if (mention[kMentionTypeKey] != 'page') {
      continue;
    }
    final targetId = mention[kMentionPageIdKey];
    if (targetId is! String || targetId.isEmpty) {
      continue;
    }
    final refBlockId = mention[kMentionBlockIdKey];
    final resolvedBlockId =
        (refBlockId is String && refBlockId.isNotEmpty) ? refBlockId : blockId;
    if (!seen.add('$targetId#$resolvedBlockId')) {
      continue;
    }
    refs.add(
      PageRef(
        sourceId: sourceId,
        targetId: targetId,
        blockId: resolvedBlockId,
        context: snippet.trim(),
      ),
    );
  }
  return refs;
}

/// 一处"未链接提及"：正文里出现了别的页面标题，但只是纯文本。
class UnlinkedMentionRef {
  const UnlinkedMentionRef({
    required this.nodeId,
    required this.start,
    required this.length,
    required this.targetId,
    required this.title,
  });

  final String nodeId;
  final int start;
  final int length;
  final String targetId;
  final String title;
}

/// 一段文本节点（供 [findUnlinkedMentionsInNodes] 使用）。
class TextNodeInput {
  const TextNodeInput({
    required this.nodeId,
    required this.text,
    required this.deltaJson,
  });

  final String nodeId;
  final String text;
  final List<dynamic> deltaJson;
}

/// 在若干文本节点里找"可以变成引用的纯文本标题"。
///
/// 规则（够用且保守）：
/// - 只匹配其它页面的标题（长度 ≥ [minTitleLength]），同一个目标页只提示一次；
/// - 跳过已经被 `@` 引用的区间（避免重复提示）；
/// - 先匹配更长的标题（避免"客户"命中"客户拜访记录"的一部分）。
List<UnlinkedMentionRef> findUnlinkedMentionsInNodes({
  required String sourceId,
  required List<TextNodeInput> nodes,
  required Map<String, String> titles,
  int minTitleLength = 2,
  int maxResults = 8,
}) {
  final candidates = titles.entries
      .where(
        (entry) =>
            entry.key != sourceId &&
            entry.key.isNotEmpty &&
            entry.value.trim().length >= minTitleLength,
      )
      .map((entry) => (id: entry.key, title: entry.value.trim()))
      .toList()
    ..sort((a, b) => b.title.length.compareTo(a.title.length));
  if (candidates.isEmpty) {
    return const [];
  }

  final results = <UnlinkedMentionRef>[];
  final alreadySuggested = <String>{};

  for (final node in nodes) {
    if (node.text.isEmpty) {
      continue;
    }
    // 已经是指用的字符区间 + 已经引用过的目标页
    final mentionedRanges = <(int, int)>[];
    // 本节点里已经被我们"建议过"的区间：避免同一个片段又被更短的标题命中一次
    final suggestedRanges = <(int, int)>[];
    final mentionedTargets = <String>{};
    var offset = 0;
    for (final op in node.deltaJson) {
      if (op is! Map) {
        continue;
      }
      final insert = op['insert'];
      final length = insert is String ? insert.length : 0;
      final attributes = op['attributes'];
      if (attributes is Map) {
        final mention = attributes[kMentionAttributeKey];
        if (mention is Map) {
          mentionedRanges.add((offset, offset + length));
          final pageId = mention[kMentionPageIdKey];
          if (pageId is String) {
            mentionedTargets.add(pageId);
          }
        }
      }
      offset += length;
    }

    for (final candidate in candidates) {
      if (mentionedTargets.contains(candidate.id) ||
          alreadySuggested.contains(candidate.id)) {
        continue;
      }
      var index = node.text.indexOf(candidate.title);
      while (index >= 0) {
        final end = index + candidate.title.length;
        final overlaps = mentionedRanges.any(
          (range) => index < range.$2 && end > range.$1,
        ) ||
            suggestedRanges.any(
              (range) => index < range.$2 && end > range.$1,
            );
        if (!overlaps) {
          results.add(
            UnlinkedMentionRef(
              nodeId: node.nodeId,
              start: index,
              length: candidate.title.length,
              targetId: candidate.id,
              title: candidate.title,
            ),
          );
          alreadySuggested.add(candidate.id);
          suggestedRanges.add((index, end));
          break;
        }
        index = node.text.indexOf(candidate.title, index + 1);
      }
      if (results.length >= maxResults) {
        return results;
      }
    }
  }
  return results;
}
