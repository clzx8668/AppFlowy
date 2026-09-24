// 双链引用解析验证（只在开发机上跑，不属于产品代码）：
//   cd E:\Dev\AppFlowy
//   dart --packages=frontend/appflowy_flutter/.dart_tool/package_config.json \
//        doc/tools/kb_links_probe.dart
//
// 覆盖：普通页面提及、块引用（带 block_id）、同一块内重复提及去重、
// 日期/链接提及（必须被忽略）、自引用（由仓储层过滤）。
import 'package:app_kb_links/app_kb_links.dart';

void main() {
  final delta = <dynamic>[
    {'insert': '今天和 '},
    {
      'insert': '客户拜访记录',
      'attributes': {
        'mention': {'type': 'page', 'page_id': 'page-A'},
      },
    },
    {'insert': ' 里提到的方案，另外 '},
    {
      'insert': '客户拜访记录',
      'attributes': {
        'mention': {'type': 'page', 'page_id': 'page-A'},
      },
    },
    {'insert': ' 这一段' },
    {
      'insert': '报价单要点',
      'attributes': {
        'mention': {'type': 'page', 'page_id': 'page-B', 'block_id': 'block-9'},
      },
    },
    {
      'insert': '2026-09-25',
      'attributes': {
        'mention': {'type': 'date', 'date': '2026-09-25'},
      },
    },
    {
      'insert': 'https://example.com',
      'attributes': {
        'mention': {'type': 'link', 'url': 'https://example.com'},
      },
    },
  ];

  final refs = extractPageRefsFromDelta(
    sourceId: 'doc-1',
    blockId: 'block-1',
    deltaJson: delta,
    context: '今天和 客户拜访记录 里提到的方案，另外 客户拜访记录 这一段',
  );

  print('refs=${refs.length}（期望 2：page-A 去重后 1 条 + page-B 块引用 1 条）');
  for (final ref in refs) {
    print(
      '  target=${ref.targetId} block=${ref.blockId} '
      'context=${ref.context}',
    );
  }

  final hasBlockRef = refs.any((r) => r.blockId == 'block-9');
  final deduped = refs.where((r) => r.targetId == 'page-A').length == 1;
  final ignoredOthers =
      refs.every((r) => r.targetId == 'page-A' || r.targetId == 'page-B');
  print('块引用识别=${hasBlockRef} 去重=${deduped} 忽略日期/链接=${ignoredOthers}');
}
