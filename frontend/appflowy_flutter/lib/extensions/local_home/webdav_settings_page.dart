import 'dart:async';

import 'package:app_webdav_sync/app_webdav_sync.dart';
import 'package:appflowy/extensions/webdav_entry.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// WebDAV 快照同步设置页。
///
/// 交互原则（与蓝图一致）：
/// - **绝不自动覆盖**：只有在"远端独有更新"时才提示拉取，且必须用户确认；
///   两边都变了 → 弹出冲突对话框让用户选"保留本地 / 使用远端"；
/// - 每次恢复前自动本地备份，恢复后提示立即重启（内核库在运行中不冻结）。
class WebDavSettingsPage extends StatefulWidget {
  const WebDavSettingsPage({super.key, required this.workspaceId});

  final String workspaceId;

  @override
  State<WebDavSettingsPage> createState() => _WebDavSettingsPageState();
}

class _WebDavSettingsPageState extends State<WebDavSettingsPage> {
  WebDavConfigRepository? _repository;
  WebDavConfig? _config;
  WebDavSnapshotSyncService? _service;
  SyncState _state = const SyncState();
  bool _loading = true;
  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  @override
  void dispose() {
    _service?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final repository = await webDavConfigRepository();
      final config = await repository.load();
      final service = await createWebDavSyncService(
        workspaceId: widget.workspaceId,
      );
      final state = await service?.state() ?? const SyncState();
      if (!mounted) {
        return;
      }
      setState(() {
        _repository = repository;
        _config = config;
        _service = service;
        _state = state;
        _loading = false;
      });
    } catch (e) {
      Log.error('[WebDAV] 初始化失败：$e');
      if (mounted) {
        setState(() {
          _status = '初始化失败：$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _editConfig() async {
    final repository = _repository;
    if (repository == null) {
      return;
    }
    final current = _config ??
        const WebDavConfig(baseUrl: '', username: '', password: '');
    final baseUrl = TextEditingController(text: current.baseUrl);
    final username = TextEditingController(text: current.username);
    final password = TextEditingController(text: current.password);
    final remoteDir = TextEditingController(text: current.remoteDir);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('WebDAV 配置'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: baseUrl,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'https://dav.example.com/dav',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: username,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码',
                  helperText: '只存本机业务库，不上传',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: remoteDir,
                decoration: const InputDecoration(
                  labelText: '远端目录',
                  hintText: '/AppFlowySnapshots',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (saved != true) {
      return;
    }
    final config = WebDavConfig(
      baseUrl: baseUrl.text.trim(),
      username: username.text.trim(),
      password: password.text,
      remoteDir: remoteDir.text.trim().isEmpty
          ? '/AppFlowySnapshots'
          : remoteDir.text.trim(),
    );
    await repository.save(config);
    _service?.dispose();
    final service = await createWebDavSyncService(
      workspaceId: widget.workspaceId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _config = config;
      _service = service;
      _status = '配置已保存';
    });
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final message = await action();
      if (mounted) {
        setState(() => _status = message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = '失败：${e.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<String> _testConnection() async {
    final service = _service;
    if (service == null) {
      return '请先填写并保存配置';
    }
    await service.testConnection();
    return '连接成功，远端目录可用';
  }

  Future<String> _upload() async {
    final service = _service;
    if (service == null) {
      return '请先填写并保存配置';
    }
    final local = await service.createLocalSnapshot(
      beforeCapture: prepareLocalDataForSnapshot,
    );
    final manifest = await service.upload(local);
    await _refreshState();
    return '已上传快照 ${manifest.id}（${manifest.files.length} 个文件，'
        '${(manifest.totalSizeInBytes / 1024 / 1024).toStringAsFixed(1)} MB）';
  }

  Future<String> _checkAndPull() async {
    final service = _service;
    if (service == null) {
      return '请先填写并保存配置';
    }
    final (action, local, remote) = await service.plan();
    switch (action) {
      case SyncAction.upToDate:
        return '本地与远端一致（哈希 ${local.manifest.zipSha256.substring(0, 8)}）';
      case SyncAction.firstUpload:
        if (await _confirm('远端还没有快照', '要把当前数据作为第一个快照上传吗？')) {
          return _upload();
        }
        return '已取消上传';
      case SyncAction.uploadLocal:
        if (await _confirm('只有本地有新改动', '远端没有变化，要把本地快照上传吗？')) {
          return _upload();
        }
        return '已取消上传';
      case SyncAction.downloadRemote:
        if (await _confirm(
          '远端有新快照',
          '远端快照：${remote?.manifest.createdAt.toString().substring(0, 19)}'
              '（设备 ${remote?.manifest.deviceName}）\n'
              '本地没有新改动，是否下载并恢复？\n'
              '（恢复前会自动备份本机数据，恢复后需要重启应用）',
        )) {
          return _restoreFrom(service, remote!);
        }
        return '已取消拉取';
      case SyncAction.conflict:
        return _resolveConflict(service, local, remote!);
    }
  }

  Future<String> _resolveConflict(
    WebDavSnapshotSyncService service,
    LocalSnapshot local,
    RemoteHead remote,
  ) async {
    final choice = await showDialog<ConflictChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('检测到同步冲突'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('本地与远端都有新改动，请选择保留哪一份：'),
            const SizedBox(height: 12),
            Text(
              '本地：${local.manifest.files.length} 个文件 · '
              '${local.manifest.zipSha256.substring(0, 8)}',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            Text(
              '远端：${remote.manifest.files.length} 个文件 · '
              '${remote.manifest.zipSha256.substring(0, 8)} · '
              '${remote.manifest.createdAt.toString().substring(0, 19)}',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(ConflictChoice.cancel),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(ConflictChoice.useRemote),
            child: const Text('使用远端'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(ConflictChoice.keepLocal),
            child: const Text('保留本地'),
          ),
        ],
      ),
    );
    switch (choice) {
      case ConflictChoice.keepLocal:
        return _upload();
      case ConflictChoice.useRemote:
        return _restoreFrom(service, remote);
      case ConflictChoice.cancel:
      case null:
        return '冲突未处理（本地与远端都没有被修改）';
    }
  }

  Future<String> _restoreFrom(
    WebDavSnapshotSyncService service,
    RemoteHead remote,
  ) async {
    // 下载 + 校验（下载阶段不需要数据库）
    final bytes = await service.download(remote);
    await prepareLocalDataForRestore();
    final report = await service.downloadAndRestoreFromBytes(remote, bytes);
    await _refreshState();
    if (mounted) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('恢复完成'),
          content: Text(
            '已恢复 ${report.restoredFiles} 个文件。\n'
            '恢复前的本机数据已备份到：\n${report.backupPath}\n\n'
            '内核数据库需要重启应用才会重新加载。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('稍后手动重启'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                SystemNavigator.pop();
              },
              child: const Text('立即退出应用'),
            ),
          ],
        ),
      );
    }
    return '已恢复远端快照（重启应用后生效）';
  }

  Future<void> _refreshState() async {
    final state = await _service?.state() ?? const SyncState();
    if (!mounted) {
      return;
    }
    setState(() => _state = state);
  }

  Future<bool> _confirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = _config;
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 快照同步')),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          config == null || !config.isConfigured
                              ? '未配置'
                              : '已配置',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          config == null || !config.isConfigured
                              ? '填入任意兼容 WebDAV 的网盘地址即可开始同步'
                              : '${config.baseUrl}\n目录：${config.remoteDir}\n'
                                  '账号：${config.username}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _state.lastSyncedAt == null
                              ? '尚未同步过'
                              : '上次同步：${_state.lastSyncedAt.toString().substring(0, 19)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => unawaited(_editConfig()),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('配置'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => unawaited(_run(_testConnection)),
                      icon: const Icon(Icons.wifi_tethering, size: 18),
                      label: const Text('测试连接'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed:
                          _busy ? null : () => unawaited(_run(_upload)),
                      icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: const Text('上传快照'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _busy
                          ? null
                          : () => unawaited(_run(_checkAndPull)),
                      icon: const Icon(Icons.cloud_download_outlined, size: 18),
                      label: const Text('检查并拉取'),
                    ),
                  ],
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(minHeight: 3),
                ],
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: theme.colorScheme.surfaceContainerHigh,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(_status, style: theme.textTheme.bodySmall),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  '说明\n'
                  '· 快照包含：业务库（闪念/CRM/日记/AI 记忆）、内核 Core 库与 CRDT 库、附件目录；\n'
                  '· 每个文件与整个压缩包都有 sha256 校验，下载后逐项比对；\n'
                  '· 只在"远端独有更新"时才会提示拉取；两边都改过会弹冲突选择，绝不自动覆盖；\n'
                  '· 恢复前自动把本机数据打包备份到数据目录，恢复后需重启应用。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    height: 1.6,
                  ),
                ),
              ],
            ),
    );
  }
}
