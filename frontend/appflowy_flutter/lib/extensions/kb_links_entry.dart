import 'package:app_biz_store/app_biz_store.dart';
import 'package:app_kb_links/app_kb_links.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

/// 装配双链服务：独立业务库里的 `doc_links` / `doc_link_index` 两张表。
Future<LinkService> createLinkService() async {
  final baseDirectory = await getIt<ApplicationDataStorage>().getPath();
  final database = await BusinessDatabase.open(
    directory: baseDirectory,
    migrations: kKbLinkMigrations,
  );
  return LinkService(LinkRepositoryImpl(database));
}

/// 全库视图 id → 标题（用于反链显示与目标标题补全）。
Future<Map<String, String>> loadViewTitles() async {
  final result = await ViewBackendService.getAllViews();
  final views = result.toNullable()?.items ?? const <ViewPB>[];
  return {
    for (final view in views)
      view.id: view.name.isEmpty ? '未命名页面' : view.name,
  };
}

/// 解析一篇内核文档里的**页面引用（出链）**。
///
/// 依据：AppFlowy 的 `@` 提及把引用写在文本的属性里 ——
/// `mention: {type: 'page'|'date'|'link', page_id, block_id?}`，
/// 其中 `type == 'page'` 就是页面引用（带 `block_id` 时是**块引用**）。
/// 这里只读取，不写内核。
Future<List<PageRef>> collectPageRefsOfDocument({
  required String documentId,
  int contextLength = 80,
}) async {
  try {
    final result = await DocumentService().getDocument(documentId: documentId);
    final document = result.fold((s) => s.toDocument(), (f) => null);
    if (document == null) {
      return const [];
    }
    final refs = <PageRef>[];
    final nodes = NodeIterator(
      document: document,
      startNode: document.root,
    ).toList();
    for (final node in nodes) {
      final delta = node.delta;
      if (delta == null || delta.isEmpty) {
        continue;
      }
      // 上下文片段：把提及本身（占位符 `$`）剔掉，只留同段落里的正文，
      // 否则"整段只有提及"时会显示一个没有信息量的 `$`。
      final contextBuffer = StringBuffer();
      for (final op in delta) {
        if (op.attributes?[kMentionAttributeKey] != null) {
          continue;
        }
        if (op is TextInsert) {
          contextBuffer.write(op.text);
        }
      }
      final context = contextBuffer
          .toString()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      // 解析逻辑放在扩展包里（纯函数），这里只负责把编辑器的 delta 喂进去
      refs.addAll(
        extractPageRefsFromDelta(
          sourceId: documentId,
          blockId: node.id,
          deltaJson: delta.toJson(),
          context: context,
          contextLength: contextLength,
        ),
      );
    }
    return refs;
  } catch (e) {
    Log.error('[双链] 解析文档引用失败 $documentId：$e');
    return const [];
  }
}

/// 刷新某篇文档的出链索引（打开文档时调用，成本 = 读一篇文档）。
Future<int> indexDocumentLinks({
  required LinkService service,
  required String documentId,
  String title = '',
  Map<String, String>? titles,
}) async {
  final refs = await collectPageRefsOfDocument(documentId: documentId);
  await service.indexDocument(
    documentId: documentId,
    title: title,
    refs: refs,
    targetTitles: titles ?? const {},
  );
  return refs.length;
}

/// 全量重建索引：遍历所有文档页面（设置页的"重建双链索引"入口）。
Future<(int, int)> rebuildLinkIndex({
  required LinkService service,
  void Function(int done, int total)? onProgress,
}) async {
  final titles = await loadViewTitles();
  final result = await ViewBackendService.getAllViews();
  final views = (result.toNullable()?.items ?? const <ViewPB>[])
      .where(
        (view) =>
            view.layout == ViewLayoutPB.Document ||
            view.layout == ViewLayoutPB.Grid ||
            view.layout == ViewLayoutPB.Board,
      )
      .toList(growable: false);

  await service.clear();
  var done = 0;
  var links = 0;
  for (final view in views) {
    links += await indexDocumentLinks(
      service: service,
      documentId: view.id,
      title: titles[view.id] ?? '',
      titles: titles,
    );
    done++;
    onProgress?.call(done, views.length);
  }
  return (done, links);
}
