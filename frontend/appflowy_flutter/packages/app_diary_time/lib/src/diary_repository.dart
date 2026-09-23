import 'package:app_biz_store/app_biz_store.dart';

import 'diary_entry.dart';

/// 日记表（独立业务库）。
const String kDiaryTable = 'diary_entries';

const List<BusinessMigration> kDiaryMigrations = [
  BusinessMigration('diary', 1, [
    '''
    CREATE TABLE IF NOT EXISTS $kDiaryTable (
      date_key TEXT PRIMARY KEY,
      mood TEXT NOT NULL DEFAULT '',
      weather TEXT NOT NULL DEFAULT '',
      location TEXT NOT NULL DEFAULT '',
      document_id TEXT,
      updated_at INTEGER NOT NULL
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_diary_updated_at '
        'ON $kDiaryTable (updated_at DESC);',
  ]),
];

/// 日记仓储契约。
abstract interface class DiaryRepository {
  Future<DiaryEntry?> entryOf(String dateKey);

  /// 区间查询（用于月历标记），日期键闭区间。
  Future<List<DiaryEntry>> entriesBetween(
    String startDateKey,
    String endDateKey,
  );

  Future<void> upsert(DiaryEntry entry);
}

class DiaryRepositoryImpl implements DiaryRepository {
  DiaryRepositoryImpl(this._db);

  final BusinessDatabase _db;

  @override
  Future<DiaryEntry?> entryOf(String dateKey) async {
    final rows = _db.raw.select(
      'SELECT * FROM $kDiaryTable WHERE date_key = ?;',
      [dateKey],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _fromRow(rows.first);
  }

  @override
  Future<List<DiaryEntry>> entriesBetween(
    String startDateKey,
    String endDateKey,
  ) async {
    final rows = _db.raw.select(
      'SELECT * FROM $kDiaryTable WHERE date_key >= ? AND date_key <= ? '
      'ORDER BY date_key ASC;',
      [startDateKey, endDateKey],
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> upsert(DiaryEntry entry) async {
    _db.raw.execute(
      'INSERT OR REPLACE INTO $kDiaryTable '
      '(date_key, mood, weather, location, document_id, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?);',
      [
        entry.dateKey,
        entry.mood,
        entry.weather,
        entry.location,
        entry.documentId,
        entry.updatedAt.millisecondsSinceEpoch,
      ],
    );
  }

  DiaryEntry _fromRow(Row row) {
    return DiaryEntry(
      dateKey: row['date_key'] as String,
      mood: row['mood'] as String? ?? '',
      weather: row['weather'] as String? ?? '',
      location: row['location'] as String? ?? '',
      documentId: row['document_id'] as String?,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }
}
