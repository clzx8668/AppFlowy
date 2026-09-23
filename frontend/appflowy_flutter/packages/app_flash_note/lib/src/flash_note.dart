/// 一条闪念记录。
///
/// 数据落点（蓝图：业务数据只放自有库，块数据才进内核）：
/// - 文本与元数据存业务库（本文件）；
/// - 用户选择"落成文档"后，正文进入内核 Document，本记录只保存 view id 关联。
class FlashNote {
  const FlashNote({
    required this.id,
    required this.text,
    required this.createdAt,
    this.documentId,
    this.archived = false,
  });

  final String id;
  final String text;
  final DateTime createdAt;

  /// 已落成内核文档时对应的 view id。
  final String? documentId;

  /// 是否已整理（从收件箱归档）。
  final bool archived;

  bool get hasDocument => documentId != null && documentId!.isNotEmpty;

  FlashNote copyWith({String? documentId, bool? archived}) {
    return FlashNote(
      id: id,
      text: text,
      createdAt: createdAt,
      documentId: documentId ?? this.documentId,
      archived: archived ?? this.archived,
    );
  }
}
