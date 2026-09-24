import 'page_ref.dart';
import 'link_repository.dart';

/// 双链服务：把"某篇文档的出链"写进索引，并回答"谁引用了我"。
///
/// 设计取向（阶段一，够用且不碰内核）：
/// - 索引按需建立：打开一篇文档时解析它的引用并刷新该文档的出链；
/// - 需要全量时（设置里的"重建索引"）由 App 侧遍历全部文档调用 [indexDocument]；
/// - 引用关系只存 id + 标题 + 上下文片段，正文仍在内核里（蓝图：不复制正文）。
class LinkService {
  LinkService(this._repository);

  final LinkRepository _repository;

  Future<void> indexDocument({
    required String documentId,
    String title = '',
    required List<PageRef> refs,
    Map<String, String> targetTitles = const {},
  }) {
    return _repository.replaceLinksFor(
      sourceId: documentId,
      sourceTitle: title,
      refs: refs,
      targetTitles: targetTitles,
    );
  }

  /// 反向链接：谁引用了我。
  Future<List<DocLink>> backlinksOf(String documentId) =>
      _repository.backlinksOf(documentId);

  /// 出链：我引用了谁。
  Future<List<DocLink>> outgoingOf(String documentId) =>
      _repository.outgoingOf(documentId);

  Future<(int, int)> stats() => _repository.stats();

  Future<void> clear() => _repository.clear();

  Future<void> removeDocument(String documentId) =>
      _repository.removeDocument(documentId);
}
