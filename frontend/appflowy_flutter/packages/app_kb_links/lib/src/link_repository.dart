import 'package:app_biz_store/app_biz_store.dart';

import 'page_ref.dart';

/// 出链索引表：一行 = 一处引用（同一文档对同一目标的多处引用按块区分）。
const String kDocLinkTable = 'doc_links';

/// 索引进度表：记录某篇文档最后一次被索引的时间与出链数量。
const String kDocLinkIndexTable = 'doc_link_index';

const List<BusinessMigration> kKbLinkMigrations = [
  BusinessMigration('kb_links', 1, [
    '''
    CREATE TABLE IF NOT EXISTS $kDocLinkTable (
      source_id TEXT NOT NULL,
      target_id TEXT NOT NULL,
      block_id TEXT NOT NULL DEFAULT '',
      context TEXT NOT NULL DEFAULT '',
      source_title TEXT NOT NULL DEFAULT '',
      target_title TEXT NOT NULL DEFAULT '',
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (source_id, target_id, block_id)
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_doc_links_target '
        'ON $kDocLinkTable (target_id);',
    'CREATE INDEX IF NOT EXISTS idx_doc_links_source '
        'ON $kDocLinkTable (source_id);',
    '''
    CREATE TABLE IF NOT EXISTS $kDocLinkIndexTable (
      source_id TEXT PRIMARY KEY,
      ref_count INTEGER NOT NULL DEFAULT 0,
      indexed_at INTEGER NOT NULL
    );
    ''',
  ]),
];

/// 链接索引仓储。
abstract interface class LinkRepository {
  /// 某页的**反向链接**（谁引用了我）。
  Future<List<DocLink>> backlinksOf(String targetId);

  /// 某页的**出链**（我引用了谁）。
  Future<List<DocLink>> outgoingOf(String sourceId);

  /// 用最新一次解析结果**替换**某文档的全部出链（幂等）。
  ///
  /// 之所以"全量替换"而不是增量：文档里的提及可能被删除/移动，
  /// 增量很难判断；单篇文档的引用数量很小，全量替换更可靠。
  Future<void> replaceLinksFor({
    required String sourceId,
    required String sourceTitle,
    required List<PageRef> refs,
    Map<String, String> targetTitles = const {},
  });

  /// 清除某文档的索引（文档被删除时调用）。
  Future<void> removeDocument(String sourceId);

  /// 统计：已索引文档数 / 总链接数。
  Future<(int, int)> stats();

  /// 清库（重建索引前调用）。
  Future<void> clear();
}

class LinkRepositoryImpl implements LinkRepository {
  LinkRepositoryImpl(this._db);

  final BusinessDatabase _db;

  @override
  Future<List<DocLink>> backlinksOf(String targetId) async {
    final rows = _db.raw.select(
      'SELECT * FROM $kDocLinkTable WHERE target_id = ? '
      'ORDER BY updated_at DESC;',
      [targetId],
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<List<DocLink>> outgoingOf(String sourceId) async {
    final rows = _db.raw.select(
      'SELECT * FROM $kDocLinkTable WHERE source_id = ? '
      'ORDER BY updated_at DESC;',
      [sourceId],
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> replaceLinksFor({
    required String sourceId,
    required String sourceTitle,
    required List<PageRef> refs,
    Map<String, String> targetTitles = const {},
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.raw.execute('BEGIN;');
    try {
      _db.raw.execute(
        'DELETE FROM $kDocLinkTable WHERE source_id = ?;',
        [sourceId],
      );
      for (final ref in refs) {
        // 自引用不入库（自己引用自己在反链里没有价值）
        if (ref.targetId.isEmpty || ref.targetId == sourceId) {
          continue;
        }
        _db.raw.execute(
          'INSERT OR REPLACE INTO $kDocLinkTable '
          '(source_id, target_id, block_id, context, source_title, '
          'target_title, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?);',
          [
            sourceId,
            ref.targetId,
            ref.blockId,
            ref.context,
            sourceTitle,
            targetTitles[ref.targetId] ?? '',
            now,
          ],
        );
      }
      _db.raw.execute(
        'INSERT OR REPLACE INTO $kDocLinkIndexTable '
        '(source_id, ref_count, indexed_at) VALUES (?, ?, ?);',
        [sourceId, refs.length, now],
      );
      _db.raw.execute('COMMIT;');
    } catch (e) {
      _db.raw.execute('ROLLBACK;');
      rethrow;
    }
  }

  @override
  Future<void> removeDocument(String sourceId) async {
    _db.raw.execute(
      'DELETE FROM $kDocLinkTable WHERE source_id = ?;',
      [sourceId],
    );
    _db.raw.execute(
      'DELETE FROM $kDocLinkIndexTable WHERE source_id = ?;',
      [sourceId],
    );
  }

  @override
  Future<(int, int)> stats() async {
    final docCount = _db.raw.select(
      'SELECT COUNT(*) AS c FROM $kDocLinkIndexTable;',
    );
    final linkCount = _db.raw.select(
      'SELECT COUNT(*) AS c FROM $kDocLinkTable;',
    );
    return (
      (docCount.first['c'] as int?) ?? 0,
      (linkCount.first['c'] as int?) ?? 0,
    );
  }

  @override
  Future<void> clear() async {
    _db.raw.execute('DELETE FROM $kDocLinkTable;');
    _db.raw.execute('DELETE FROM $kDocLinkIndexTable;');
  }

  DocLink _fromRow(Row row) {
    return DocLink(
      sourceId: row['source_id'] as String,
      targetId: row['target_id'] as String,
      blockId: row['block_id'] as String? ?? '',
      context: row['context'] as String? ?? '',
      sourceTitle: row['source_title'] as String? ?? '',
      targetTitle: row['target_title'] as String? ?? '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }
}
