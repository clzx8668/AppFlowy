// WebDAV 快照同步端到端验证（只在开发机上跑，不属于产品代码）：
//   cd E:\Dev\AppFlowy
//   dart --packages=frontend/appflowy_flutter/.dart_tool/package_config.json \
//        doc/tools/webdav_sync_probe.dart
//
// 脚本内起一个最小 WebDAV 服务（PROPFIND/MKCOL/PUT/GET/HEAD/DELETE），
// 用真实的同步服务跑：首次上传 → 一致 → 本地变更 → 冲突判定 → 下载恢复 + 哈希校验。
import 'dart:convert';
import 'dart:io';

import 'package:app_webdav_sync/app_webdav_sync.dart';

final Map<String, List<int>> _objects = {};

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8099);
  server.listen(_handle);
  print('测试 WebDAV 服务已启动：http://127.0.0.1:8099');

  final dataDir = Directory.systemTemp.createTempSync('af-webdav-');
  final workspace = 'ws-test';
  _seedLocalData(dataDir.path, workspace, 'local-v1');

  final config = WebDavConfig(
    baseUrl: 'http://127.0.0.1:8099',
    username: 'tester',
    password: 'secret',
    remoteDir: '/sync-test',
  );
  final service = WebDavSnapshotSyncService(
    config: config,
    dataDirectory: dataDir.path,
    workspaceId: workspace,
    deviceName: 'probe-device',
  );

  await service.testConnection();
  print('1) 连接与建目录：OK');

  var (action, local, remote) = await service.plan();
  print('2) 首次判定 = $action（期望 firstUpload）');
  await service.upload(local);

  (action, local, remote) = await service.plan();
  print('3) 上传后判定 = $action（期望 upToDate）');

  _seedLocalData(dataDir.path, workspace, 'local-v2');
  (action, local, remote) = await service.plan();
  print('4) 本地变更后判定 = $action（期望 uploadLocal）');

  // 模拟"另一台设备也改了并上传" → 本地/远端都变 → 冲突
  final otherDir = Directory.systemTemp.createTempSync('af-webdav-other-');
  _seedLocalData(otherDir.path, workspace, 'remote-v9');
  final other = WebDavSnapshotSyncService(
    config: config,
    dataDirectory: otherDir.path,
    workspaceId: workspace,
    deviceName: 'other-device',
  );
  final otherLocal = await other.createLocalSnapshot();
  await other.upload(otherLocal);

  (action, local, remote) = await service.plan();
  print('5) 双端都变后判定 = $action（期望 conflict）');

  // 用户选择"使用远端"：下载 + 校验 + 恢复
  final head = remote!;
  final bytes = await service.download(head);
  final report = await service.downloadAndRestoreFromBytes(head, bytes);
  final restoredBody = File(
    '${dataDir.path}/$workspace/collab_db/CURRENT',
  ).readAsStringSync();
  print(
    '6) 恢复完成：${report.restoredFiles} 个文件，正文=$restoredBody'
    '（期望 remote-v9），备份=${report.backupPath.split(Platform.pathSeparator).last}',
  );

  (action, local, remote) = await service.plan();
  print('7) 恢复后判定 = $action（期望 upToDate）');

  // 篡改一个字节 → 校验必须失败（哈希校验生效）
  final tampered = List<int>.from(bytes);
  tampered[tampered.length ~/ 2] = tampered[tampered.length ~/ 2] ^ 0xFF;
  try {
    await service.downloadAndRestoreFromBytes(head, tampered);
    print('8) 篡改检测：未拦截 ✗');
  } catch (e) {
    print('8) 篡改检测：已拦截 ✔ (${e.toString().split(':').first})');
  }

  service.dispose();
  other.dispose();
  await server.close(force: true);
}

void _seedLocalData(String root, String workspace, String body) {
  final business = Directory('$root/business')..createSync(recursive: true);
  File('${business.path}/business.db').writeAsStringSync('business-db-$body');
  final ws = Directory('$root/$workspace')..createSync(recursive: true);
  File('${ws.path}/flowy-database.db').writeAsStringSync('core-db-$body');
  final collab = Directory('${ws.path}/collab_db')..createSync(recursive: true);
  File('${collab.path}/CURRENT').writeAsStringSync('collab-current-$body');
}

Future<void> _handle(HttpRequest request) async {
  final path = request.uri.path;
  switch (request.method) {
    case 'PROPFIND':
      request.response
        ..statusCode = 207
        ..headers.contentType = ContentType('application', 'xml')
        ..write(
          '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">'
          '<d:response><d:href>$path</d:href><d:propstat><d:prop>'
          '<d:resourcetype><d:collection/></d:resourcetype>'
          '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
          '</d:response></d:multistatus>',
        );
    case 'MKCOL':
      request.response.statusCode = _objects.containsKey(path) ? 405 : 201;
    case 'PUT':
      final chunks = await request.fold<List<int>>(
        <int>[],
        (acc, chunk) => acc..addAll(chunk),
      );
      _objects[path] = chunks;
      request.response.statusCode = 201;
    case 'GET':
      final object = _objects[path];
      if (object == null) {
        request.response.statusCode = 404;
      } else {
        request.response
          ..statusCode = 200
          ..add(object);
      }
    case 'HEAD':
      request.response.statusCode = _objects.containsKey(path) ? 200 : 404;
    case 'DELETE':
      _objects.remove(path);
      request.response.statusCode = 204;
    default:
      request.response.statusCode = 405;
  }
  await request.response.close();
}
