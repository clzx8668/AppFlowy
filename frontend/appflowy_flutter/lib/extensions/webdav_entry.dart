import 'dart:io';

import 'package:app_biz_store/app_biz_store.dart';
import 'package:app_webdav_sync/app_webdav_sync.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:flutter/foundation.dart';

/// 装配 WebDAV 快照同步：
/// - 配置存本机业务库（`webdav_config` 表，含密码，仅本机）；
/// - 同步状态存 `<数据目录>/business/webdav_sync_state.json`；
/// - 快照包含双库（业务库 + 内核 Core/CRDT 库）与附件目录。
Future<WebDavConfigRepository> webDavConfigRepository() async {
  final database = await _businessDatabase();
  return WebDavConfigRepository(database);
}

/// 已配置好时返回同步服务，否则返回 null（UI 据此提示先配置）。
Future<WebDavSnapshotSyncService?> createWebDavSyncService({
  required String workspaceId,
}) async {
  final baseDirectory = await getIt<ApplicationDataStorage>().getPath();
  final database = await _businessDatabase();
  final config = await WebDavConfigRepository(database).load();
  if (config == null || !config.isConfigured) {
    return null;
  }
  return WebDavSnapshotSyncService(
    config: config,
    dataDirectory: baseDirectory,
    workspaceId: workspaceId,
    deviceName: currentDeviceName(),
  );
}

/// 取快照前调用：把业务库 WAL 落盘，尽量减小"拷贝到一半"的窗口。
Future<void> prepareLocalDataForSnapshot() async {
  try {
    BusinessDatabase.instance?.raw.execute('PRAGMA wal_checkpoint(TRUNCATE);');
  } catch (e) {
    debugPrint('[WebDAV] WAL checkpoint 失败（忽略）：$e');
  }
}

/// 恢复快照前调用：关闭业务库连接，避免文件被占用/回写。
Future<void> prepareLocalDataForRestore() async {
  BusinessDatabase.instance?.close();
}

/// 设备名（写进快照清单，用于人工识别是哪台设备传的）。
String currentDeviceName() {
  try {
    final host = Platform.localHostname;
    if (host.isNotEmpty && host != 'localhost') {
      return host;
    }
  } catch (_) {
    // Android 上 localHostname 可能不可用，忽略
  }
  return Platform.operatingSystem;
}

Future<BusinessDatabase> _businessDatabase() async {
  final baseDirectory = await getIt<ApplicationDataStorage>().getPath();
  // 迁移用同一个表集合（业务库已按模块记录，重复注册是安全的）
  return BusinessDatabase.open(
    directory: baseDirectory,
    migrations: kWebDavMigrations,
  );
}
