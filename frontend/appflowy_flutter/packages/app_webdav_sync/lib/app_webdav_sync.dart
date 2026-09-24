/// WebDAV 快照同步模块（v0：双库 + 附件全量快照、哈希校验、冲突人工选择）。
///
/// 蓝图定位：放弃 AppFlowy Cloud，用 WebDAV 做"双库 + 附件"统一快照同步；阶段一全量、阶段二增量。
///
/// 复用：
/// - 数据目录定位：`ApplicationDataStorage.getPath()`（Android 实测 `files/data_dev/`）
///   其中包含业务库 `business/business.db`、内核 Core 库 `<工作区>/flowy-database.db`、
///   CRDT 库 `<工作区>/collab_db/`；
/// - 打包：`archive`（zip）、`crypto`（sha256）。
///
/// 自研：
/// - [SnapshotBuilder]：按清单打包双库 + 附件，生成 `manifest.json` 与逐文件哈希；
/// - [WebDavClient]：MKCOL / PUT / GET / HEAD / PROPFIND / DELETE 极简实现；
/// - [WebDavSnapshotSyncService]：三方比较（本地 / 远端 / 上次同步基线）判定冲突，
///   **绝不自动覆盖**，冲突一律交给用户选择；
/// - [SnapshotRestorer]：先备份、再逐文件校验哈希、最后改名替换（旧的留档不删除）。
///
/// 安全边界（务必知悉）：
/// - 内核库（RocksDB 目录 + SQLite）在应用运行时**无法原子冻结**，因此恢复后必须重启应用；
///   恢复前会自动把将被覆盖的文件打包成 `sync_backup_<时间戳>.zip`；
/// - 配置里包含密码，只存在本机业务库（不上传、不外发）。
library app_webdav_sync;

import 'package:app_biz_store/app_biz_store.dart';

import 'src/webdav_sync_service.dart' show WebDavConfigLike;

export 'src/snapshot.dart';
export 'src/webdav_client.dart' show WebDavClient, RemoteFileNotFound;
export 'src/webdav_sync_service.dart';

/// 模块标识，用于日志与路由前缀。
const String kAppWebdavSyncPackage = 'app_webdav_sync';

/// WebDAV 配置表（本机业务库）。
const String kWebDavConfigTable = 'webdav_config';

const List<BusinessMigration> kWebDavMigrations = [
  BusinessMigration('webdav', 1, [
    '''
    CREATE TABLE IF NOT EXISTS $kWebDavConfigTable (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      base_url TEXT NOT NULL DEFAULT '',
      username TEXT NOT NULL DEFAULT '',
      password TEXT NOT NULL DEFAULT '',
      remote_dir TEXT NOT NULL DEFAULT '/AppFlowySnapshots',
      updated_at INTEGER NOT NULL
    );
    ''',
  ]),
];

/// WebDAV 连接配置。
class WebDavConfig implements WebDavConfigLike {
  const WebDavConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.remoteDir = '/AppFlowySnapshots',
  });

  @override
  final String baseUrl;
  @override
  final String username;
  @override
  final String password;
  @override
  final String remoteDir;

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty && username.trim().isNotEmpty;

  WebDavConfig copyWith({
    String? baseUrl,
    String? username,
    String? password,
    String? remoteDir,
  }) {
    return WebDavConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      remoteDir: remoteDir ?? this.remoteDir,
    );
  }
}

/// 配置仓储：读写本机业务库里的 WebDAV 配置（单行表）。
class WebDavConfigRepository {
  WebDavConfigRepository(this._db);

  final BusinessDatabase _db;

  Future<WebDavConfig?> load() async {
    final rows = _db.raw.select('SELECT * FROM $kWebDavConfigTable WHERE id = 1;');
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return WebDavConfig(
      baseUrl: row['base_url'] as String? ?? '',
      username: row['username'] as String? ?? '',
      password: row['password'] as String? ?? '',
      remoteDir: row['remote_dir'] as String? ?? '/AppFlowySnapshots',
    );
  }

  Future<void> save(WebDavConfig config) async {
    _db.raw.execute(
      'INSERT OR REPLACE INTO $kWebDavConfigTable '
      '(id, base_url, username, password, remote_dir, updated_at) '
      'VALUES (1, ?, ?, ?, ?, ?);',
      [
        config.baseUrl,
        config.username,
        config.password,
        config.remoteDir,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }
}
