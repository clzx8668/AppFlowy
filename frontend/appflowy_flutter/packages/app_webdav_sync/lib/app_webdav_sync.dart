/// WebDAV 快照同步模块（骨架）
///
/// 蓝图定位：放弃 AppFlowy Cloud，用 WebDAV 做"双库 + 附件"统一快照同步；阶段一全量、阶段二增量。
///
/// 复用：
/// - 数据目录定位：`ApplicationDataStorage.getPath()`（桌面实测 `%APPDATA%\io.appflowy\AppFlowy\data_dev\`）
///   其中包含 Core 库（`<uid>/flowy-database.db`）、CRDT 库（`<uid>/collab_db/`）、索引与缓存
/// - 打包：上游已依赖 `archive`（zip）
///
/// 自研：
/// - 快照冻结：暂停前台写入与后台任务后打包（SQLite 需连同 `-wal/-shm`），上游无现成 API（勿改内核，需专项验证）
/// - WebDAV 上传/下载、版本哈希校验、差异比对
/// - 冲突策略：人工选择保留本地/拉取远端，绝不自动覆盖
library app_webdav_sync;

/// 模块标识，用于日志与路由前缀。
const String kAppWebdavSyncPackage = 'app_webdav_sync';

/// WebDAV 连接配置（骨架）。
class WebDavConfig {
  const WebDavConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.remoteDir = '/AppFlowySnapshots',
  });

  final String baseUrl;
  final String username;
  final String password;
  final String remoteDir;
}

/// 快照描述（骨架）：一个快照 = 一次完整打包，含版本、时间、哈希、大小。
class SnapshotInfo {
  const SnapshotInfo({
    required this.id,
    required this.createdAt,
    required this.sha256,
    required this.sizeInBytes,
    this.deviceName,
  });

  final String id;
  final DateTime createdAt;
  final String sha256;
  final int sizeInBytes;
  final String? deviceName;
}

/// 同步服务契约（骨架）。
abstract interface class WebDavSyncService {
  /// 打包本地数据目录为快照。
  Future<SnapshotInfo> createSnapshot();

  /// 上传快照到 WebDAV。
  Future<void> uploadSnapshot(SnapshotInfo snapshot);

  /// 列出远端快照（按时间倒序）。
  Future<List<SnapshotInfo>> listRemoteSnapshots();

  /// 下载并校验快照；冲突时交由上层让用户选择。
  Future<void> downloadSnapshot(SnapshotInfo snapshot);
}
