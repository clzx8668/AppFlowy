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

  // ---- 未链接提及：正文写了别的页面标题但还没做引用 ----
  final unlinked = findUnlinkedMentionsInNodes(
    sourceId: 'doc-1',
    nodes: [
      TextNodeInput(
        nodeId: 'n1',
        text: '今天和 客户拜访记录 聊了很久，顺便提到 客户',
        deltaJson: [
          {'insert': '今天和 客户拜访记录 聊了很久，顺便提到 客户'},
        ],
      ),
      TextNodeInput(
        nodeId: 'n2',
        text: '参考 报价单要点 里的数据',
        deltaJson: [
          {'insert': '参考 '},
          {
            'insert': '报价单要点',
            'attributes': {
              'mention': {'type': 'page', 'page_id': 'page-B'},
            },
          },
          {'insert': ' 里的数据'},
        ],
      ),
    ],
    titles: {
      'doc-1': '本页（应被排除）',
      'page-A': '客户拜访记录',
      'page-B': '报价单要点',
      'page-C': '客户',
      'page-D': '客',
    },
  );
  print('未链接提及=${unlinked.map((r) => '${r.title}@${r.nodeId}:${r.start}').toList()}');
  print(
    '（期望 2 条：客户拜访记录@n1:4 与 客户@n1:21 —— 两处都是正文里真实出现的页面名；\n'
    '  说明：同一片段不会被更短标题重复命中；"报价单要点"已是指用不提示；\n'
    '  单字标题"客"被最短长度规则排除；"本页（应被排除）"被自引用排除）',
  );
}
