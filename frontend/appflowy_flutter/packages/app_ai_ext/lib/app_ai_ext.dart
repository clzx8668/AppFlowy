/// AI 扩展模块（v0：本地摘要 + 标签 + 记忆库）。
///
/// 蓝图定位：AI 可无限迭代的个人智能记忆系统；本地优先、可自选模型。
///
/// 复用（**不重写 AI**）：
/// - 抽象层：`lib/ai/service/appflowy_ai_service.dart` 的 `AIRepository`（流式补全、内置提示词）
/// - 注册点：`lib/startup/deps_resolver.dart` 的 `getIt.registerFactory<AIRepository>(...)`
///   → 本包提供自己的实现即可整体替换/包装上游 `AppFlowyAIService`
/// - 已有 UI：`lib/ai/widgets/**`（提示词输入、模型选择）、`lib/plugins/ai_chat/**`（AI 聊天页）
/// - 本地模型：内核 `flowy-ai` 已支持 Ollama，可完全离线
///
/// 本包自研（v0 已落地）：
/// - **本地摘要/标签**：`LocalTextDigester`（纯 Dart、零网络、零依赖，可离线跑）
/// - **AI 记忆库**：摘要与标签写进独立业务库（`ai_digests` 表，与内核 Core 库分离）
/// - **可插拔**：`TextDigester` 是接口，后续接云端/本地大模型只需再加一个实现
///
/// 数据边界：只保存"摘要文本 + 标签"，原始文档仍在内核里，不复制正文（蓝图要求）。
library app_ai_ext;

import 'package:app_biz_store/app_biz_store.dart';

export 'src/local_text_digester.dart';

/// 模块标识，用于日志与路由前缀。
const String kAppAiExtPackage = 'app_ai_ext';

/// AI 记忆库表：一篇内容对应一条摘要记录。
const String kAiDigestTable = 'ai_digests';

const List<BusinessMigration> kAiMigrations = [
  BusinessMigration('ai', 1, [
    '''
    CREATE TABLE IF NOT EXISTS $kAiDigestTable (
      source_id TEXT PRIMARY KEY,
      source_title TEXT NOT NULL DEFAULT '',
      summary TEXT NOT NULL DEFAULT '',
      tags TEXT NOT NULL DEFAULT '',
      engine TEXT NOT NULL DEFAULT 'local',
      updated_at INTEGER NOT NULL
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_ai_digest_updated_at '
        'ON $kAiDigestTable (updated_at DESC);',
  ]),
];

/// 一条 AI 摘要记录（记忆卡片）。
class AiDigest {
  const AiDigest({
    required this.sourceId,
    required this.summary,
    this.sourceTitle = '',
    this.tags = const [],
    this.engine = 'local',
    required this.updatedAt,
  });

  /// 来源标识：内核文档 id（也可以是一段自由文本的哈希）。
  final String sourceId;
  final String sourceTitle;
  final String summary;
  final List<String> tags;

  /// 生成引擎：`local`（本地抽取式）/ 后续 `openai`、`ollama` 等。
  final String engine;
  final DateTime updatedAt;

  /// 标签在业务库里用 \u0001 连接（避免和标签内的逗号冲突）。
  static String encodeTags(List<String> tags) => tags.join('\u0001');

  static List<String> decodeTags(String raw) =>
      raw.isEmpty ? const [] : raw.split('\u0001');
}

/// 摘要结果。
class AiDigestResult {
  const AiDigestResult({
    required this.summary,
    this.tags = const [],
    this.engine = 'local',
  });

  final String summary;
  final List<String> tags;
  final String engine;
}

/// 文本摘要器契约：本地抽取式 / 云端大模型 / 本地 Ollama 都实现它。
abstract interface class TextDigester {
  String get engine;

  Future<AiDigestResult> digest(String text, {String? title});
}

/// 文档正文读取网关（依赖倒置：扩展包不直接依赖内核与编辑器）。
abstract interface class AiSourceGateway {
  /// 读取内核文档的纯文本正文（失败返回空串）。
  Future<String> plainTextOf(String documentId);
}

/// AI 记忆库仓储。
abstract interface class AiDigestRepository {
  Future<AiDigest?> of(String sourceId);

  Future<List<AiDigest>> recent({int limit = 50});

  Future<void> upsert(AiDigest digest);

  Future<void> remove(String sourceId);
}

class AiDigestRepositoryImpl implements AiDigestRepository {
  AiDigestRepositoryImpl(this._db);

  final BusinessDatabase _db;

  @override
  Future<AiDigest?> of(String sourceId) async {
    final rows = _db.raw.select(
      'SELECT * FROM $kAiDigestTable WHERE source_id = ?;',
      [sourceId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _fromRow(rows.first);
  }

  @override
  Future<List<AiDigest>> recent({int limit = 50}) async {
    final rows = _db.raw.select(
      'SELECT * FROM $kAiDigestTable ORDER BY updated_at DESC LIMIT ?;',
      [limit],
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> upsert(AiDigest digest) async {
    _db.raw.execute(
      'INSERT OR REPLACE INTO $kAiDigestTable '
      '(source_id, source_title, summary, tags, engine, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?);',
      [
        digest.sourceId,
        digest.sourceTitle,
        digest.summary,
        AiDigest.encodeTags(digest.tags),
        digest.engine,
        digest.updatedAt.millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<void> remove(String sourceId) async {
    _db.raw.execute(
      'DELETE FROM $kAiDigestTable WHERE source_id = ?;',
      [sourceId],
    );
  }

  AiDigest _fromRow(Row row) {
    return AiDigest(
      sourceId: row['source_id'] as String,
      sourceTitle: row['source_title'] as String? ?? '',
      summary: row['summary'] as String? ?? '',
      tags: AiDigest.decodeTags(row['tags'] as String? ?? ''),
      engine: row['engine'] as String? ?? 'local',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }
}

/// AI 服务：把"某篇内容"变成"一条记忆"（摘要 + 标签），并落进业务库。
class AiService {
  AiService({
    required AiDigestRepository repository,
    required TextDigester digester,
    AiSourceGateway? sourceGateway,
  })  : _repository = repository,
        _digester = digester,
        _sourceGateway = sourceGateway;

  final AiDigestRepository _repository;
  final TextDigester _digester;
  final AiSourceGateway? _sourceGateway;

  /// 对内核文档生成摘要（读正文 → 摘要 → 落库）。
  Future<AiDigest> digestDocument({
    required String documentId,
    String title = '',
  }) async {
    final text = await _sourceGateway?.plainTextOf(documentId) ?? '';
    if (text.trim().isEmpty) {
      throw Exception('这篇内容还没有正文，先写点东西再生成摘要');
    }
    return _persist(
      sourceId: documentId,
      title: title,
      result: await _digester.digest(text, title: title),
    );
  }

  /// 对一段临时文本生成摘要（AI 标签页的"随手贴"入口）。
  Future<AiDigest> digestText({required String text, String title = ''}) async {
    if (text.trim().isEmpty) {
      throw Exception('请输入要摘要的文本');
    }
    final sourceId = 'text:${_stableHash(text)}';
    return _persist(
      sourceId: sourceId,
      title: title.isEmpty ? '随手贴' : title,
      result: await _digester.digest(text, title: title),
    );
  }

  Future<List<AiDigest>> memories({int limit = 50}) =>
      _repository.recent(limit: limit);

  /// 用**指定的来源 id** 生成摘要（例如 CRM 实体：`crm:<entityId>`），
  /// 便于把 CRM 客户/项目的"记忆卡片"和内核页面的摘要放在同一个记忆库里。
  Future<AiDigest> digestTextWithSource({
    required String sourceId,
    required String title,
    required String text,
  }) async {
    if (text.trim().isEmpty) {
      throw Exception('内容为空，暂时无法生成摘要');
    }
    return _persist(
      sourceId: sourceId,
      title: title,
      result: await _digester.digest(text, title: title),
    );
  }

  Future<AiDigest?> memoryOf(String sourceId) => _repository.of(sourceId);

  Future<void> forget(String sourceId) => _repository.remove(sourceId);

  Future<AiDigest> _persist({
    required String sourceId,
    required String title,
    required AiDigestResult result,
  }) async {
    final digest = AiDigest(
      sourceId: sourceId,
      sourceTitle: title,
      summary: result.summary,
      tags: result.tags,
      engine: result.engine,
      updatedAt: DateTime.now(),
    );
    await _repository.upsert(digest);
    return digest;
  }

  int _stableHash(String text) {
    var hash = 0;
    for (final unit in text.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }
}
