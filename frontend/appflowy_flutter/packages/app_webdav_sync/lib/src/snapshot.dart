import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// zip 条目固定时间戳（1980-01-01，zip 格式允许的最小值）。
///
/// 目的：**让快照哈希只取决于内容**，这样"内容没变 → 哈希相同"才有意义，
/// 冲突判定与"是否需要同步"都依赖这一点。
const int _fixedModTime = 315532800;

/// 快照里被打包的一个文件。
class SnapshotFile {
  const SnapshotFile({
    required this.relativePath,
    required this.sha256,
    required this.sizeInBytes,
  });

  /// 相对数据目录的路径（zip 内路径），例如 `business/business.db`。
  final String relativePath;
  final String sha256;
  final int sizeInBytes;

  Map<String, Object> toJson() => {
        'path': relativePath,
        'sha256': sha256,
        'size': sizeInBytes,
      };

  static SnapshotFile fromJson(Map<String, Object?> json) => SnapshotFile(
        relativePath: json['path'] as String,
        sha256: json['sha256'] as String,
        sizeInBytes: (json['size'] as num).toInt(),
      );
}

/// 快照清单：写进 zip（`manifest.json`），也随 `latest.json` 上传，
/// 用于**哈希校验**（下载后逐个文件比对）与冲突判定。
class SnapshotManifest {
  const SnapshotManifest({
    required this.id,
    required this.createdAt,
    required this.deviceName,
    required this.files,
    required this.zipSha256,
    required this.contentHash,
  });

  final String id;
  final DateTime createdAt;
  final String deviceName;
  final List<SnapshotFile> files;

  /// 整个 zip 的 sha256（用于"传输完整性"校验）。
  final String zipSha256;

  /// **内容哈希**：由「排序后的 相对路径+文件哈希」算出，与打包时间无关。
  ///
  /// 同步判定（是否需要上传/下载、是否冲突）只看它 ——
  /// 这样"内容没变 → 哈希不变"才成立（zip 里含 manifest.json 与时间戳，不能直接用 zip 哈希判定）。
  final String contentHash;

  int get totalSizeInBytes =>
      files.fold<int>(0, (sum, file) => sum + file.sizeInBytes);

  SnapshotManifest copyWith({String? zipSha256, String? contentHash}) =>
      SnapshotManifest(
        id: id,
        createdAt: createdAt,
        deviceName: deviceName,
        files: files,
        zipSha256: zipSha256 ?? this.zipSha256,
        contentHash: contentHash ?? this.contentHash,
      );

  Map<String, Object?> toJson() => {
        'version': 1,
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'deviceName': deviceName,
        'zipSha256': zipSha256,
        'contentHash': contentHash,
        'totalSize': totalSizeInBytes,
        'files': files.map((file) => file.toJson()).toList(),
      };

  static SnapshotManifest fromJson(Map<String, Object?> json) =>
      SnapshotManifest(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        deviceName: (json['deviceName'] as String?) ?? '',
        zipSha256: (json['zipSha256'] as String?) ?? '',
        contentHash: (json['contentHash'] as String?) ?? '',
        files: (json['files'] as List<Object?>)
            .map((e) => SnapshotFile.fromJson(e as Map<String, Object?>))
            .toList(),
      );
}

/// 快照打包结果。
class LocalSnapshot {
  const LocalSnapshot({required this.manifest, required this.bytes});

  final SnapshotManifest manifest;
  final List<int> bytes;
}

/// 快照打包器：把数据目录里的关键文件（双库 + 附件目录）打成一个 zip。
///
/// 打包范围（阶段一：全量快照）：
/// - `business/`：**独立业务库**（闪念/CRM/日记/AI 记忆），SQLite；
/// - `<工作区>/flowy-database.db`：内核 Core 库（视图/文件夹元数据）；
/// - `<工作区>/collab_db/`：内核 CRDT 库（文档正文）；
/// - `attachments/`、`upload/`：附件目录（存在才打包）。
///
/// 注意：内核库是 RocksDB 目录 + SQLite 文件，**不在运行中做原子冻结**，
/// 所以恢复端会先做本地备份、并要求重启应用（见 [SnapshotRestorer]）。
class SnapshotBuilder {
  const SnapshotBuilder({
    required this.dataDirectory,
    required this.workspaceId,
    required this.deviceName,
  });

  /// 应用数据目录（`ApplicationDataStorage.getPath()`，包含 `business/` 与工作区子目录）。
  final String dataDirectory;
  final String workspaceId;
  final String deviceName;

  /// 相对路径 → 绝对路径 的打包清单。
  Map<String, String> sourceFiles() {
    final sources = <String, String>{};

    final businessDir = Directory(p.join(dataDirectory, 'business'));
    if (businessDir.existsSync()) {
      for (final entity in businessDir.listSync()) {
        if (entity is File) {
          final name = p.basename(entity.path);
          // WAL/SHM 一起带走，保证 SQLite 一致性
          if (name.startsWith('business.db')) {
            sources['business/$name'] = entity.path;
          }
        }
      }
    }

    final workspaceDir = Directory(p.join(dataDirectory, workspaceId));
    if (workspaceDir.existsSync()) {
      final coreDb = File(p.join(workspaceDir.path, 'flowy-database.db'));
      if (coreDb.existsSync()) {
        sources['$workspaceId/flowy-database.db'] = coreDb.path;
      }
      final collabDir = Directory(p.join(workspaceDir.path, 'collab_db'));
      if (collabDir.existsSync()) {
        for (final entity in collabDir.listSync(recursive: true)) {
          if (entity is File) {
            final relative =
                p.relative(entity.path, from: workspaceDir.path).replaceAll('\\', '/');
            sources['$workspaceId/$relative'] = entity.path;
          }
        }
      }
    }

    for (final attachments in ['attachments', 'upload', 'images']) {
      final dir = Directory(p.join(dataDirectory, workspaceId, attachments));
      if (!dir.existsSync()) {
        continue;
      }
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File) {
          final relative =
              p.relative(entity.path, from: workspaceDir.path).replaceAll('\\', '/');
          sources['$workspaceId/$relative'] = entity.path;
        }
      }
    }

    return sources;
  }

  Future<LocalSnapshot> build() async {
    final sources = sourceFiles();
    final archive = Archive();
    final files = <SnapshotFile>[];

    for (final entry in sources.entries) {
      final bytes = await File(entry.value).readAsBytes();
      final digest = sha256.convert(bytes).toString();
      files.add(
        SnapshotFile(
          relativePath: entry.key,
          sha256: digest,
          sizeInBytes: bytes.length,
        ),
      );
      archive.addFile(
        ArchiveFile(entry.key, bytes.length, bytes)
          // 固定时间戳：让"内容不变 → 快照哈希不变"，否则每次打包时间不同会导致哈希永远变化
          ..lastModTime = _fixedModTime,
      );
    }

    final createdAt = DateTime.now();
    final id = 'snap-${createdAt.millisecondsSinceEpoch}';
    final manifest = SnapshotManifest(
      id: id,
      createdAt: createdAt,
      deviceName: deviceName,
      files: files,
      zipSha256: '',
      contentHash: _contentHashOf(files),
    );

    // manifest.json 自己也进 zip；zip 的 sha256 作为"整体哈希"写回 manifest（供 latest.json 使用）。
    final manifestBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
    );
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes)
        ..lastModTime = _fixedModTime,
    );

    final zipped = ZipEncoder().encode(archive);
    final zipBytes = zipped ?? const <int>[];
    final zipDigest = sha256.convert(zipBytes).toString();

    return LocalSnapshot(
      manifest: manifest.copyWith(zipSha256: zipDigest),
      bytes: zipBytes,
    );
  }

  /// 内容哈希：路径 + 文件哈希，排序后拼串取 sha256（与时间、设备无关）。
  String _contentHashOf(List<SnapshotFile> files) {
    final sorted = files.toList()
      ..sort((a, b) => a.relativePath.compareTo(b.relativePath));
    final buffer = StringBuffer();
    for (final file in sorted) {
      buffer.writeln('${file.relativePath}:${file.sha256}');
    }
    return sha256.convert(utf8.encode(buffer.toString())).toString();
  }
}

/// 恢复结果。
class RestoreReport {
  const RestoreReport({
    required this.restoredFiles,
    required this.backupPath,
  });

  final int restoredFiles;

  /// 恢复前自动打的本地备份（出事可以回滚）。
  final String backupPath;
}

/// 快照恢复器：**先备份、再校验、最后替换**。
///
/// 校验分两层：
/// 1. `zipSha256`：整个 zip 的 sha256 必须与 `latest.json` 声明一致（传输完整性）；
/// 2. 逐个文件 sha256：必须与 `manifest.json` 一致（内容完整性）。
///
/// 替换方式：把被覆盖的文件/目录**改名备份**（不删除），再写入新内容，
/// 这样即使恢复出错，用户的数据还在原地可以手动找回（蓝图：绝不自动丢数据）。
class SnapshotRestorer {
  const SnapshotRestorer({required this.dataDirectory});

  final String dataDirectory;

  Future<RestoreReport> restore({
    required List<int> zipBytes,
    required SnapshotManifest remoteManifest,
  }) async {
    final actualZipHash = sha256.convert(zipBytes).toString();
    if (remoteManifest.zipSha256.isNotEmpty &&
        actualZipHash != remoteManifest.zipSha256) {
      throw Exception('快照整体哈希不一致（可能传输损坏）');
    }

    final archive = ZipDecoder().decodeBytes(zipBytes);
    final manifestFile = archive.files.firstWhere(
      (file) => file.name == 'manifest.json',
      orElse: () => throw Exception('快照缺少 manifest.json'),
    );
    final manifest = SnapshotManifest.fromJson(
      jsonDecode(utf8.decode(manifestFile.content as List<int>))
          as Map<String, Object?>,
    );

    // 先全部校验，再动任何文件
    final verified = <(String, List<int>)>[];
    for (final file in manifest.files) {
      final archived = archive.files.firstWhere(
        (f) => f.name == file.relativePath,
        orElse: () => throw Exception('快照缺少文件：${file.relativePath}'),
      );
      final bytes = archived.content as List<int>;
      final digest = sha256.convert(bytes).toString();
      if (digest != file.sha256) {
        throw Exception('文件哈希不一致：${file.relativePath}');
      }
      verified.add((file.relativePath, bytes));
    }

    // 备份当前数据（整个 business/ 与工作区里将被覆盖的文件）
    final backupTs = DateTime.now().millisecondsSinceEpoch;
    final backupPath = p.join(dataDirectory, 'sync_backup_$backupTs.zip');
    await _backupCurrent(verified.map((e) => e.$1).toList(), backupPath);

    var restored = 0;
    for (final (relativePath, bytes) in verified) {
      final target = File(p.join(dataDirectory, relativePath));
      if (target.existsSync()) {
        // 覆盖前把旧文件改名留档。
        // ⚠️ 必须挪到**快照范围之外**的目录：否则这些 `.replaced-*` 残留文件
        // 会被下一次快照一起打包，导致"恢复完还是判定为本地有改动"（内容哈希永远收敛不了）。
        final archived = File(
          p.join(
            dataDirectory,
            'sync_restore_history',
            '$backupTs',
            relativePath,
          ),
        );
        archived.parent.createSync(recursive: true);
        target.renameSync(archived.path);
      }
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes, flush: true);
      restored++;
    }

    return RestoreReport(restoredFiles: restored, backupPath: backupPath);
  }

  Future<void> _backupCurrent(List<String> relativePaths, String backupPath) async {
    final archive = Archive();
    for (final relativePath in relativePaths) {
      final file = File(p.join(dataDirectory, relativePath));
      if (!file.existsSync()) {
        continue;
      }
      final bytes = await file.readAsBytes();
      archive.addFile(
        ArchiveFile(relativePath, bytes.length, bytes)
          ..lastModTime = _fixedModTime,
      );
    }
    final zipped = ZipEncoder().encode(archive);
    if (zipped == null) {
      return;
    }
    await File(backupPath).writeAsBytes(zipped, flush: true);
  }
}
