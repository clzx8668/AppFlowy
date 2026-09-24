/// 一条"页面引用"（出链）。
///
/// 来源：内核文档里的 `@` 提及（inline attribute `mention`，其 `type == page`），
/// 上游本来就有"页面提及 / 块引用"能力（提及里可带 `page_id` 与 `block_id`），
/// 我们只是把这些引用**索引起来**，从而补上上游缺失的"反向链接"。
class PageRef {
  const PageRef({
    required this.sourceId,
    required this.targetId,
    this.blockId = '',
    this.context = '',
  });

  /// 引用方：所在的文档 id。
  final String sourceId;

  /// 被引用方：页面 id（块引用时仍是页面 id）。
  final String targetId;

  /// 块引用时的块 id（普通页面提及为空）。
  final String blockId;

  /// 上下文片段（提及所在段落文本），用于在反链里显示"在哪句话里被引用"。
  final String context;

  PageRef copyWith({String? context}) => PageRef(
        sourceId: sourceId,
        targetId: targetId,
        blockId: blockId,
        context: context ?? this.context,
      );
}

/// 索引里的一条链接记录（带双方标题，便于 UI 直接渲染，不必回查内核）。
class DocLink {
  const DocLink({
    required this.sourceId,
    required this.targetId,
    required this.blockId,
    required this.context,
    required this.sourceTitle,
    required this.targetTitle,
    required this.updatedAt,
  });

  final String sourceId;
  final String targetId;
  final String blockId;
  final String context;
  final String sourceTitle;
  final String targetTitle;
  final DateTime updatedAt;

  bool get isBlockRef => blockId.isNotEmpty;
}
