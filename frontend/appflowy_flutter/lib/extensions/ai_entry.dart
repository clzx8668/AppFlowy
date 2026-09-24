import 'package:app_ai_ext/app_ai_ext.dart';
import 'package:app_biz_store/app_biz_store.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

/// 装配 AI 服务：本地业务库（`ai_digests` 表）+ 本地抽取式摘要器 + 内核文档正文读取。
///
/// 为什么不直接调用上游 `AIRepository`：v0 要保证"零配置、离线可用"，
/// 先用纯 Dart 抽取式摘要把"摘要 → 标签 → 记忆库"这条链路跑通；
/// 后续接大模型（云端或本地 Ollama）只需实现 [TextDigester] 再在这里替换一行装配。
Future<AiService> createAiService() async {
  final baseDirectory = await getIt<ApplicationDataStorage>().getPath();
  final database = await BusinessDatabase.open(
    directory: baseDirectory,
    migrations: kAiMigrations,
  );
  return AiService(
    repository: AiDigestRepositoryImpl(database),
    digester: const LocalTextDigester(),
    sourceGateway: const _CoreAiSourceGateway(),
  );
}

/// 内核文档正文读取：走内核既有 API（`getDocument` → 编辑器文档模型 → 抽取文本），
/// 不引入任何新的内核能力，也不修改内核代码。
class _CoreAiSourceGateway implements AiSourceGateway {
  const _CoreAiSourceGateway();

  @override
  Future<String> plainTextOf(String documentId) async {
    try {
      final result = await DocumentService().getDocument(documentId: documentId);
      final document = result.fold((s) => s.toDocument(), (f) => null);
      if (document == null) {
        return '';
      }
      final buffer = StringBuffer();
      final nodes = NodeIterator(
        document: document,
        startNode: document.root,
      ).toList();
      for (final node in nodes) {
        final delta = node.delta;
        if (delta != null && delta.isNotEmpty) {
          buffer
            ..write(delta.toPlainText())
            ..write('\n');
        }
      }
      return buffer.toString().trim();
    } catch (e) {
      Log.error('[AI] 读取文档正文失败：$documentId, $e');
      return '';
    }
  }
}
