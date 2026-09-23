/// 独立业务数据库（Sqlite）—— 二次开发基础设施包。
///
/// 蓝图约束（《整体架构设计规范》二、数据架构设计）：
/// - Core 官方数据库（内核 sqlite / CRDT）**只读、不新增表**；
/// - CRM、业务统计、日记索引等业务数据放**独立 Sqlite**，自主管理表结构，方便迁移与同步。
///
/// 因此本包：
/// - 数据库文件放在应用数据目录下的 `business/` 子目录（与内核 `data_dev/` 内的库文件互不相干）；
/// - 用 `PRAGMA user_version` 做版本管理，各业务模块通过 [BusinessMigration] 注册自己的建表语句；
/// - 只提供连接/事务/迁移，不包含任何业务表（业务表由各扩展包自带）。
library app_biz_store;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

// 业务模块只需要这几类 sqlite3 类型，由基础包统一再导出，避免各业务包重复依赖。
export 'package:sqlite3/sqlite3.dart'
    show Database, Row, ResultSet, SqliteException;

/// 一次 schema 迁移：所属模块 + 模块内版本号 + 建表/改表语句。
///
/// 采用「按模块记录」的方式（见 `_biz_migrations` 表），
/// 避免各业务模块都从 1 开始编号时互相覆盖（曾因此漏建 CRM 表）。
class BusinessMigration {
  const BusinessMigration(this.module, this.version, this.statements);

  /// 模块标识，例如 `flash_note` / `crm` / `diary`。
  final String module;
  final int version;
  final List<String> statements;
}

/// 业务库连接。
///
/// 用法：
/// ```dart
/// final db = await BusinessDatabase.open(
///   directory: appDataDir,
///   migrations: [BusinessMigration(1, ['CREATE TABLE ...'])],
/// );
/// ```
class BusinessDatabase {
  BusinessDatabase._(this._db, this.path);

  final Database _db;

  /// 业务库文件绝对路径（快照同步时需与 Core 库一起打包）。
  final String path;

  /// 数据库文件名（放在 `<应用数据目录>/business/` 下）。
  static const String fileName = 'business.db';

  /// 业务库子目录名。
  static const String directoryName = 'business';

  static BusinessDatabase? _instance;

  /// 已打开的业务库（未打开时为 null）。
  static BusinessDatabase? get instance => _instance;

  /// 打开（或复用）业务库，并按 [migrations] 升级 schema。
  static Future<BusinessDatabase> open({
    required String directory,
    required List<BusinessMigration> migrations,
  }) async {
    final existing = _instance;
    if (existing != null) {
      // 业务库已经被打开过（例如闪念模块先初始化）：仍需应用本次传入的迁移，
      // 否则后加载的模块（CRM/日记等）建表会被跳过。
      _applyMigrations(existing._db, migrations);
      return existing;
    }

    final dir = Directory(p.join(directory, directoryName));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final filePath = p.join(dir.path, fileName);

    final db = sqlite3.open(filePath);
    // 并发与一致性设置：WAL 便于快照阶段一并拷贝，外键约束开启。
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA foreign_keys = ON;');

    _applyMigrations(db, migrations);

    final store = BusinessDatabase._(db, filePath);
    _instance = store;
    return store;
  }

  static void _applyMigrations(
    Database db,
    List<BusinessMigration> migrations,
  ) {
    // 迁移记录表：按 (module, version) 记录已应用项
    db.execute(
      'CREATE TABLE IF NOT EXISTS _biz_migrations ('
      'module TEXT NOT NULL, version INTEGER NOT NULL, '
      'applied_at INTEGER NOT NULL, PRIMARY KEY (module, version));',
    );
    final applied = <String>{
      for (final row in db.select('SELECT module, version FROM _biz_migrations;'))
        '${row['module']}#${row['version']}',
    };
    final ordered = migrations.toList()
      ..sort((a, b) {
        final byModule = a.module.compareTo(b.module);
        return byModule != 0 ? byModule : a.version.compareTo(b.version);
      });
    for (final migration in ordered) {
      if (applied.contains('${migration.module}#${migration.version}')) {
        continue;
      }
      db.execute('BEGIN;');
      try {
        for (final statement in migration.statements) {
          db.execute(statement);
        }
        db.execute(
          'INSERT OR REPLACE INTO _biz_migrations (module, version, applied_at) '
          'VALUES (?, ?, ?);',
          [
            migration.module,
            migration.version,
            DateTime.now().millisecondsSinceEpoch,
          ],
        );
        db.execute('COMMIT;');
      } catch (e) {
        db.execute('ROLLBACK;');
        rethrow;
      }
    }
  }

  /// 底层连接（业务仓储使用）。
  Database get raw => _db;

  /// 关闭连接（应用退出或快照前调用）。
  void close() {
    _db.dispose();
    _instance = null;
  }
}
