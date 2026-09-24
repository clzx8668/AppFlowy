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
