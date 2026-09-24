import 'dart:async';
import 'dart:math' as math;

import 'package:app_kb_links/app_kb_links.dart';
import 'package:appflowy/extensions/kb_links_entry.dart';
import 'package:appflowy/extensions/flash_note_entry.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';

/// 知识库关系图谱：把 `doc_links` 里的引用关系画出来（节点=页面，边=引用）。
///
/// 实现取向（阶段一，不引第三方图库）：
/// - 极简力导向布局（斥力 + 边弹簧 + 向心），只算一次，结果缓存在 State 里；
/// - `CustomPainter` 画边与节点，节点大小 = 被引用次数；
/// - 点节点跳转到对应页面；底部给出"被引用最多"榜单，避免图太小时看不出信息。
class KnowledgeGraphPage extends StatefulWidget {
  const KnowledgeGraphPage({super.key});

  @override
  State<KnowledgeGraphPage> createState() => _KnowledgeGraphPageState();
}

class _KnowledgeGraphPageState extends State<KnowledgeGraphPage> {
  GraphData _graph = const GraphData(nodes: {}, edges: []);
  Map<String, Offset> _positions = const {};
  bool _loading = true;
  String _status = '';
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final service = await createLinkService();
      var graph = await service.graphData();
      // 如果还没建过索引，这里顺手补一次全库索引，避免用户看到空图
      if (graph.isEmpty) {
        await rebuildLinkIndex(service: service);
        graph = await service.graphData();
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _graph = graph;
        _positions = _layout(graph);
        _loading = false;
        _status = graph.isEmpty ? '还没有任何页面引用：在正文里用 @ 引用其它页面即可建立关系' : '';
      });
    } catch (e) {
      Log.error('[图谱] 加载失败：$e');
      if (mounted) {
        setState(() {
          _status = '加载失败：$e';
          _loading = false;
        });
      }
    }
  }

  /// 极简力导向布局：斥力（两两）+ 边弹簧 + 轻微向心，迭代若干轮后归一化到 0..1。
  Map<String, Offset> _layout(GraphData graph) {
    final ids = graph.nodes.keys.toList();
    if (ids.isEmpty) {
      return const {};
    }
    // 节点很少时力导向会把它们推到对角（看着像两个孤立点），改用整齐的环形排布
    if (ids.length <= 4) {
      const radius = 0.28;
      return {
        for (var i = 0; i < ids.length; i++)
          ids[i]: Offset(
            0.5 + radius * math.cos(2 * math.pi * i / ids.length - math.pi / 2) ,
            0.5 + radius * math.sin(2 * math.pi * i / ids.length - math.pi / 2),
          ),
      };
    }
    final random = math.Random(42); // 固定种子：同一份数据图形稳定
    final positions = <String, Offset>{
      for (var i = 0; i < ids.length; i++)
        ids[i]: Offset(
          0.5 + random.nextDouble() - 0.5,
          0.5 + random.nextDouble() - 0.5,
        ),
    };

    const iterations = 320;
    const repulsion = 0.0022;
    const springLength = 0.28;
    const springStrength = 0.06;

    for (var step = 0; step < iterations; step++) {
      final forces = <String, Offset>{for (final id in ids) id: Offset.zero};

      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final a = positions[ids[i]]!;
          final b = positions[ids[j]]!;
          var delta = a - b;
          var distance = delta.distance;
          if (distance < 0.001) {
            delta = const Offset(0.001, 0.001);
            distance = 0.0014;
          }
          final force = repulsion / (distance * distance);
          final push = delta / distance * force;
          forces[ids[i]] = forces[ids[i]]! + push;
          forces[ids[j]] = forces[ids[j]]! - push;
        }
      }

      for (final edge in graph.edges) {
        final a = positions[edge.sourceId];
        final b = positions[edge.targetId];
        if (a == null || b == null) {
          continue;
        }
        final delta = b - a;
        final distance = delta.distance == 0 ? 0.001 : delta.distance;
        final pull =
            delta / distance * ((distance - springLength) * springStrength);
        forces[edge.sourceId] = forces[edge.sourceId]! + pull;
        forces[edge.targetId] = forces[edge.targetId]! - pull;
      }

      for (final id in ids) {
        final position = positions[id]!;
        final force = forces[id]!;
        // 向心 + 阻尼步长
        final center = Offset(0.5, 0.5) - position;
        positions[id] = position + force * 0.5 + center * 0.006;
      }
    }

    // 归一化到 0..1（留 8% 边距）
    final xs = positions.values.map((p) => p.dx).toList();
    final ys = positions.values.map((p) => p.dy).toList();
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final spanX = (maxX - minX).abs() < 0.0001 ? 1.0 : maxX - minX;
    final spanY = (maxY - minY).abs() < 0.0001 ? 1.0 : maxY - minY;
    return {
      for (final id in ids)
        id: Offset(
          0.08 + (positions[id]!.dx - minX) / spanX * 0.84,
          0.08 + (positions[id]!.dy - minY) / spanY * 0.84,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = _graph.topInbound();
    return Scaffold(
      appBar: AppBar(
        title: const Text('知识库关系图谱'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading
                ? null
                : () {
                    setState(() => _loading = true);
                    unawaited(_load());
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  '${_graph.nodes.length} 个页面 · ${_graph.edges.length} 条引用',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    _status,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (!_graph.isEmpty)
                  AspectRatio(
                    aspectRatio: 1.15,
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      clipBehavior: Clip.antiAlias,
                      // 用 LayoutBuilder 拿到画布真实尺寸：点击命中的坐标换算必须基于它，
                      // 不能用页面 context 的尺寸（否则命中点整体偏移）。
                      child: LayoutBuilder(
                        builder: (context, constraints) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (details) => _onTapGraph(
                            details.localPosition,
                            constraints.biggest,
                          ),
                          child: CustomPaint(
                            size: constraints.biggest,
                            painter: _GraphPainter(
                              graph: _graph,
                              positions: _positions,
                              selectedId: _selectedId,
                              lineColor: theme.colorScheme.outlineVariant,
                              nodeColor: theme.colorScheme.primary,
                              selectedColor: theme.colorScheme.tertiary,
                              labelColor: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (top.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    '被引用最多',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final item in top)
                    InkWell(
                      onTap: () =>
                          unawaited(openDocumentByViewId(context, item.$1)),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 4,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            Text(
                              '${item.$3} 处引用',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }

  void _onTapGraph(Offset localPosition, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    String? nearest;
    var nearestDistance = double.infinity;
    _positions.forEach((id, normalized) {
      final point = Offset(
        normalized.dx * size.width,
        normalized.dy * size.height,
      );
      final distance = (point - localPosition).distance;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = id;
      }
    });
    final id = nearest;
    if (id == null || nearestDistance > 40) {
      setState(() => _selectedId = null);
      return;
    }
    // 先高亮选中，再打开页面（点一下就想进去的直觉）
    setState(() => _selectedId = id);
    unawaited(openDocumentByViewId(context, id));
  }
}

class _GraphPainter extends CustomPainter {
  const _GraphPainter({
    required this.graph,
    required this.positions,
    required this.selectedId,
    required this.lineColor,
    required this.nodeColor,
    required this.selectedColor,
    required this.labelColor,
  });

  final GraphData graph;
  final Map<String, Offset> positions;
  final String? selectedId;
  final Color lineColor;
  final Color nodeColor;
  final Color selectedColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    Offset pointOf(String id) {
      final normalized = positions[id] ?? const Offset(0.5, 0.5);
      return Offset(normalized.dx * size.width, normalized.dy * size.height);
    }

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (final edge in graph.edges) {
      if (!positions.containsKey(edge.sourceId) ||
          !positions.containsKey(edge.targetId)) {
        continue;
      }
      canvas.drawLine(
        pointOf(edge.sourceId),
        pointOf(edge.targetId),
        linePaint,
      );
    }

    for (final entry in graph.nodes.entries) {
      final point = pointOf(entry.key);
      final inbound = graph.inboundCounts[entry.key] ?? 0;
      final radius = 6.0 + math.min(inbound, 5) * 2.0;
      final isSelected = entry.key == selectedId;
      canvas.drawCircle(
        point,
        radius,
        Paint()..color = isSelected ? selectedColor : nodeColor,
      );

      final label = entry.value;
      if (label.isEmpty) {
        continue;
      }
      final textPainter = TextPainter(
        text: TextSpan(
          text: label.length > 8 ? '${label.substring(0, 8)}…' : label,
          style: TextStyle(
            fontSize: 10,
            color: labelColor,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: 90);
      textPainter.paint(
        canvas,
        point + Offset(-textPainter.width / 2, radius + 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) =>
      oldDelegate.graph != graph ||
      oldDelegate.positions != positions ||
      oldDelegate.selectedId != selectedId;
}
