import 'package:app_biz_store/app_biz_store.dart';

import 'flash_note.dart';

/// 闪念表结构（业务库，独立于内核 Core 库）。
const String kFlashNoteTable = 'flash_notes';

/// 本模块向业务库注册的迁移。
const List<BusinessMigration> kFlashNoteMigrations = [
  BusinessMigration('flash_note', 1, [
    '''
    CREATE TABLE IF NOT EXISTS $kFlashNoteTable (
      id TEXT PRIMARY KEY,
      text TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      document_id TEXT,
      archived INTEGER NOT NULL DEFAULT 0
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_flash_notes_created_at '
        'ON $kFlashNoteTable (created_at DESC);',
  ]),
];

/// 闪念仓储：只依赖业务库，不触碰内核。
class FlashNoteRepository {
  FlashNoteRepository(this._db);

  final BusinessDatabase _db;

  Future<void> insert(FlashNote note) async {
    _db.raw.execute(
      'INSERT OR REPLACE INTO $kFlashNoteTable '
      '(id, text, created_at, document_id, archived) VALUES (?, ?, ?, ?, ?);',
      [
        note.id,
        note.text,
        note.createdAt.millisecondsSinceEpoch,
        note.documentId,
        note.archived ? 1 : 0,
      ],
    );
  }

  Future<void> attachDocument(String id, String documentId) async {
    _db.raw.execute(
      'UPDATE $kFlashNoteTable SET document_id = ? WHERE id = ?;',
      [documentId, id],
    );
  }

  Future<void> setArchived(String id, bool archived) async {
    _db.raw.execute(
      'UPDATE $kFlashNoteTable SET archived = ? WHERE id = ?;',
      [archived ? 1 : 0, id],
    );
  }

  Future<void> delete(String id) async {
    _db.raw.execute('DELETE FROM $kFlashNoteTable WHERE id = ?;', [id]);
  }

  Future<List<FlashNote>> list({bool includeArchived = false}) async {
    final rows = _db.raw.select(
      'SELECT * FROM $kFlashNoteTable '
      '${includeArchived ? '' : 'WHERE archived = 0 '}'
      'ORDER BY created_at DESC;',
    );
    return rows.map(_fromRow).toList();
  }

  FlashNote _fromRow(Row row) {
    return FlashNote(
      id: row['id'] as String,
      text: row['text'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      documentId: row['document_id'] as String?,
      archived: (row['archived'] as int? ?? 0) == 1,
    );
  }
}
