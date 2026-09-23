import 'package:nanoid/nanoid.dart';

import 'flash_note.dart';
import 'flash_note_repository.dart';

/// 把闪念落成内核文档的网关。
///
/// 由 App 层注入实现（依赖反转）：扩展包不直接依赖 `appflowy_editor` 与 App 内部代码，
/// 只用这个契约表达"我需要一篇带正文的文档"，具体走内核 API 的细节留在 App 侧适配器。
abstract interface class FlashNoteDocumentGateway {
  /// 用 [text] 创建一篇文档，返回其 view id。
  ///
  /// [title] 为页面标题（取首行），[body] 为完整正文。
  Future<String> createDocument({
    required String title,
    required String body,
    required DateTime createdAt,
  });
}

/// 闪念服务：捕获 → 存储 → 落成文档 → 回看。
class FlashNoteService {
  FlashNoteService({
    required FlashNoteRepository repository,
    required FlashNoteDocumentGateway documentGateway,
  })  : _repository = repository,
        _documentGateway = documentGateway;

  final FlashNoteRepository _repository;
  final FlashNoteDocumentGateway _documentGateway;

  /// 捕获：先落库（保证不丢），再尝试落成文档。
  ///
  /// 即使文档创建失败，闪念本身也已安全保存，可在收件箱里重试。
  Future<FlashNote> capture(
    String text, {
    bool createDocument = true,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('闪念内容不能为空');
    }

    final note = FlashNote(
      id: nanoid(12),
      text: trimmed,
      createdAt: DateTime.now(),
    );
    await _repository.insert(note);

    if (!createDocument) {
      return note;
    }
    return promoteToDocument(note);
  }

  /// 把已有闪念落成内核文档（收件箱里的"转入知识库"）。
  Future<FlashNote> promoteToDocument(FlashNote note) async {
    if (note.hasDocument) {
      return note;
    }
    final lines = note.text.split('\n');
    final title = lines.first.trim().isEmpty
        ? _fallbackTitle(note.createdAt)
        : _truncate(lines.first.trim(), 40);
    final documentId = await _documentGateway.createDocument(
      title: title,
      body: note.text,
      createdAt: note.createdAt,
    );
    await _repository.attachDocument(note.id, documentId);
    return note.copyWith(documentId: documentId);
  }

  Future<void> archive(FlashNote note, {bool archived = true}) {
    return _repository.setArchived(note.id, archived);
  }

  Future<void> delete(FlashNote note) => _repository.delete(note.id);

  Future<List<FlashNote>> inbox() => _repository.list();

  static String _fallbackTitle(DateTime createdAt) {
    final m = createdAt.month.toString().padLeft(2, '0');
    final d = createdAt.day.toString().padLeft(2, '0');
    final hh = createdAt.hour.toString().padLeft(2, '0');
    final mm = createdAt.minute.toString().padLeft(2, '0');
    return '闪念 $m-$d $hh:$mm';
  }

  static String _truncate(String text, int max) {
    if (text.length <= max) {
      return text;
    }
    return '${text.substring(0, max)}…';
  }
}
