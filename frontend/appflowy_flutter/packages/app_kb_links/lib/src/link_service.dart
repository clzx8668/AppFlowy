import 'page_ref.dart';
import 'link_repository.dart';

/// 图谱里的一条边。
class GraphEdge {
  const GraphEdge({
    required this.sourceId,
    required this.targetId,
    this.isBlockRef = false,
  });

  final String sourceId;
  final String targetId;
  final bool isBlockRef;
}

/// 图谱数据：节点（id → 标题）、边、被引用/出链计数。
class GraphData {
  const GraphData({
    required this.nodes,
    required this.edges,
    this.inboundCounts = const {},
    this.outboundCounts = const {},
  });

  final Map<String, String> nodes;
  final List<GraphEdge> edges;
  final Map<String, int> inboundCounts;
  final Map<String, int> outboundCounts;

  bool get isEmpty => nodes.isEmpty;

  /// 被引用最多的页面（图谱旁的榜单用）。
  List<(String id, String title, int count)> topInbound({int limit = 8}) {
    final entries = inboundCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .take(limit)
        .map((e) => (e.key, nodes[e.key] ?? '未命名页面', e.value))
        .toList(growable: false);
  }
}

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

  /// 全库链接（关系图谱）。
  Future<List<DocLink>> allLinks({int limit = 2000}) =>
      _repository.all(limit: limit);

  /// 关系图谱数据：节点（文档 id → 标题）+ 边。
  Future<GraphData> graphData({int limit = 2000}) async {
    final links = await _repository.all(limit: limit);
    final nodes = <String, String>{};
    final edges = <GraphEdge>[];
    final inbound = <String, int>{};
    final outbound = <String, int>{};

    for (final link in links) {
      nodes.putIfAbsent(
        link.sourceId,
        () => link.sourceTitle.isEmpty ? '未命名页面' : link.sourceTitle,
      );
      nodes.putIfAbsent(
        link.targetId,
        () => link.targetTitle.isEmpty ? '未命名页面' : link.targetTitle,
      );
      if (link.sourceTitle.isNotEmpty) {
        nodes[link.sourceId] = link.sourceTitle;
      }
      if (link.targetTitle.isNotEmpty) {
        nodes[link.targetId] = link.targetTitle;
      }
      edges.add(
        GraphEdge(
          sourceId: link.sourceId,
          targetId: link.targetId,
          isBlockRef: link.isBlockRef,
        ),
      );
      inbound[link.targetId] = (inbound[link.targetId] ?? 0) + 1;
      outbound[link.sourceId] = (outbound[link.sourceId] ?? 0) + 1;
    }

    return GraphData(
      nodes: nodes,
      edges: edges,
      inboundCounts: inbound,
      outboundCounts: outbound,
    );
  }

  Future<(int, int)> stats() => _repository.stats();

  Future<void> clear() => _repository.clear();

  Future<void> removeDocument(String documentId) =>
      _repository.removeDocument(documentId);
}
