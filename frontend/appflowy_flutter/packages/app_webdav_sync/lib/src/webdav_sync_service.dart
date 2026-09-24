import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'snapshot.dart';
import 'webdav_client.dart';

/// 同步状态（本地记录"上一次同步的哈希"，用来做三方比较）。
class SyncState {
  const SyncState({
    this.lastSyncedAt,
    this.lastLocalHash = '',
    this.lastRemoteHash = '',
  });

  final DateTime? lastSyncedAt;
  final String lastLocalHash;
  final String lastRemoteHash;

  bool get hasBaseline => lastLocalHash.isNotEmpty && lastRemoteHash.isNotEmpty;

  Map<String, Object?> toJson() => {
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
        'lastLocalHash': lastLocalHash,
        'lastRemoteHash': lastRemoteHash,
      };

  static SyncState fromJson(Map<String, Object?> json) => SyncState(
        lastSyncedAt: json['lastSyncedAt'] == null
            ? null
            : DateTime.tryParse(json['lastSyncedAt'] as String),
        lastLocalHash: (json['lastLocalHash'] as String?) ?? '',
        lastRemoteHash: (json['lastRemoteHash'] as String?) ?? '',
      );
}

/// 同步状态存储（默认落地 JSON 文件，放在应用数据目录里）。
class SyncStateStore {
  SyncStateStore(this.dataDirectory);

  final String dataDirectory;

  File get _file => File(p.join(dataDirectory, 'business', 'webdav_sync_state.json'));

  Future<SyncState> load() async {
    if (!_file.existsSync()) {
      return const SyncState();
    }
    try {
      final decoded =
          jsonDecode(await _file.readAsString()) as Map<String, Object?>;
      return SyncState.fromJson(decoded);
    } catch (_) {
      return const SyncState();
    }
  }

  Future<void> save(SyncState state) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(state.toJson()), flush: true);
  }
}

/// 同步判定结果。
enum SyncAction {
  /// 本地与远端一致（无需动作）。
  upToDate,

  /// 只有本地变了 → 可以上传。
  uploadLocal,

  /// 只有远端变了 → 可以拉取。
  downloadRemote,

  /// 两边都变了（或首次同步且两边都有内容）→ **必须人工选择**。
  conflict,

  /// 远端还没有快照 → 首次上传。
  firstUpload,
}

/// 冲突时用户的选择（绝不自动覆盖）。
enum ConflictChoice {
  /// 保留本地：把本地快照上传覆盖远端。
  keepLocal,

  /// 使用远端：下载并恢复远端快照。
  useRemote,

  /// 用户放弃本次同步。
  cancel,
}

/// 远端最新快照（`latest.json`）。
class RemoteHead {
  const RemoteHead({required this.manifest, required this.objectPath});

  final SnapshotManifest manifest;

  /// 远端 zip 的路径（相对 WebDAV 根）。
  final String objectPath;

  static const String latestJsonName = 'latest.json';
}

/// WebDAV 快照同步服务（阶段一：全量快照 + 哈希校验 + 人工冲突选择）。
///
/// 远端目录结构：
/// ```
/// <remoteDir>/latest.json                 # 指向最新快照（含 manifest 与 zip 哈希）
/// <remoteDir>/snapshots/<snap-id>.zip     # 快照本体
/// ```
///
/// 冲突判定（三方比较）：
/// - 本地哈希 == base == 远端哈希 → 一致；
/// - 本地变了、远端没变 → 上传；
/// - 远端变了、本地没变 → 拉取；
/// - 两边都变了 → [SyncAction.conflict]，交给用户选择。
class WebDavSnapshotSyncService {
  WebDavSnapshotSyncService({
    required this.config,
    required this.dataDirectory,
    required this.workspaceId,
    required this.deviceName,
    WebDavClient? client,
    SyncStateStore? stateStore,
  })  : _client = client ??
            WebDavClient(
              baseUrl: config.baseUrl,
              username: config.username,
              password: config.password,
            ),
        _stateStore = stateStore ?? SyncStateStore(dataDirectory);

  final WebDavConfigLike config;
  final String dataDirectory;
  final String workspaceId;
  final String deviceName;
  final WebDavClient _client;
  final SyncStateStore _stateStore;

  String get remoteDir =>
      config.remoteDir.startsWith('/') ? config.remoteDir : '/${config.remoteDir}';

  String get _latestPath => '$remoteDir/${RemoteHead.latestJsonName}';

  Future<void> testConnection() async {
    await _client.testConnection();
    await _client.ensureDirectory(remoteDir);
    await _client.ensureDirectory('$remoteDir/snapshots');
  }

  Future<SyncState> state() => _stateStore.load();

  /// 读取远端最新快照（没有则返回 null）。
  Future<RemoteHead?> remoteHead() async {
    final text = await _client.getTextOrNull(_latestPath);
    if (text == null || text.trim().isEmpty) {
      return null;
    }
    final json = jsonDecode(text) as Map<String, Object?>;
    final manifest = SnapshotManifest.fromJson(json);
    return RemoteHead(
      manifest: manifest,
      objectPath: '$remoteDir/snapshots/${manifest.id}.zip',
    );
  }

  /// 生成一次本地快照（含计算哈希，用于判定）。
  Future<LocalSnapshot> createLocalSnapshot({
    Future<void> Function()? beforeCapture,
  }) async {
    await beforeCapture?.call();
    final builder = SnapshotBuilder(
      dataDirectory: dataDirectory,
      workspaceId: workspaceId,
      deviceName: deviceName,
    );
    return builder.build();
  }

  /// 判定本次同步该做什么（不写任何数据）。
  Future<(SyncAction, LocalSnapshot, RemoteHead?)> plan() async {
    final local = await createLocalSnapshot();
    final remote = await remoteHead();
    final base = await _stateStore.load();

    if (remote == null) {
      return (SyncAction.firstUpload, local, null);
    }

    // 判定一律用**内容哈希**（与打包时间无关），不用 zip 哈希
    final localHash = local.manifest.contentHash;
    final remoteHash = remote.manifest.contentHash;

    if (localHash == remoteHash) {
      return (SyncAction.upToDate, local, remote);
    }

    if (!base.hasBaseline) {
      // 没有基线（例如第一次配置同步）：两边都有内容 → 冲突，交给用户
      return (SyncAction.conflict, local, remote);
    }

    final localChanged = localHash != base.lastLocalHash;
    final remoteChanged = remoteHash != base.lastRemoteHash;
    if (localChanged && remoteChanged) {
      return (SyncAction.conflict, local, remote);
    }
    if (localChanged) {
      return (SyncAction.uploadLocal, local, remote);
    }
    if (remoteChanged) {
      return (SyncAction.downloadRemote, local, remote);
    }
    return (SyncAction.upToDate, local, remote);
  }

  /// 上传本地快照（并把 baseline 更新为"两边一致"）。
  Future<SnapshotManifest> upload(LocalSnapshot local) async {
    await _client.ensureDirectory('$remoteDir/snapshots');
    final objectPath = '$remoteDir/snapshots/${local.manifest.id}.zip';
    await _client.putBytes(objectPath, local.bytes);
    await _client.putText(
      _latestPath,
      const JsonEncoder.withIndent('  ').convert(local.manifest.toJson()),
    );
    await _stateStore.save(
      SyncState(
        lastSyncedAt: DateTime.now(),
        lastLocalHash: local.manifest.contentHash,
        lastRemoteHash: local.manifest.contentHash,
      ),
    );
    return local.manifest;
  }

  /// 下载远端快照（返回原始字节，是否恢复由上层决定）。
  Future<List<int>> download(RemoteHead head) => _client.getBytes(head.objectPath);

  /// 下载 + 校验 + 恢复（恢复前自动备份本地；调用方需保证已暂停写入）。
  Future<RestoreReport> downloadAndRestore(RemoteHead head) async {
    final bytes = await download(head);
    return downloadAndRestoreFromBytes(head, bytes);
  }

  /// 用"已经下载好的字节"进行校验 + 恢复。
  ///
  /// 之所以拆出来：恢复前需要先关闭本地数据库连接（文件被占用时无法替换），
  /// 因此调用方的顺序是「先下载 → 关库 → 再恢复」。
  Future<RestoreReport> downloadAndRestoreFromBytes(
    RemoteHead head,
    List<int> bytes,
  ) async {
    final restorer = SnapshotRestorer(dataDirectory: dataDirectory);
    final report = await restorer.restore(
      zipBytes: bytes,
      remoteManifest: head.manifest,
    );
    await _stateStore.save(
      SyncState(
        lastSyncedAt: DateTime.now(),
        lastLocalHash: head.manifest.contentHash,
        lastRemoteHash: head.manifest.contentHash,
      ),
    );
    return report;
  }

  /// 快速哈希（用于日志/调试：对快照字节取 sha256 前缀）。
  String shortHash(List<int> bytes) =>
      sha256.convert(bytes).toString().substring(0, 12);

  void dispose() => _client.close();
}

/// 配置契约（由包外提供实现，避免包内直接依赖业务库）。
abstract interface class WebDavConfigLike {
  String get baseUrl;

  String get username;

  String get password;

  String get remoteDir;
}
