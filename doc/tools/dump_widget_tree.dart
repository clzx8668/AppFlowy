// 无画面环境下校验桌面端 UI 是否渲染（拉 Flutter 控件树 / 渲染树）：
//   dart doc/tools/dump_widget_tree.dart <VMServiceUri> [--render] [关键字...]
//
// 用法示例（配合 `flutter run -d windows`，日志里会给 VM Service URI）：
//   dart doc/tools/dump_widget_tree.dart http://127.0.0.1:9052/TOKEN=/ LocalModulesSection
//   dart doc/tools/dump_widget_tree.dart http://127.0.0.1:9052/TOKEN=/ --render 新页面 "日历 · 日记"
//
// 为什么需要它：本机 Windows 会话抓不到 Flutter 画面（全屏/窗口截图都是黑屏），
// 用 VM Service 的 ext.flutter.debugDumpApp 直接拿控件树，就能确认某个组件到底有没有被渲染。
// 加 --render 时改拉渲染树（含每个节点的 offset/size），可用来核对"缩进/对齐"这类样式问题。
import 'dart:convert';
import 'dart:async';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法: dump_widget_tree.dart <vmServiceUri> [关键字...]');
    exit(2);
  }
  final uri = args.first;
  final rest = args.skip(1).toList();
  final useRenderTree = rest.contains('--render');
  final keywords = rest.where((arg) => arg != '--render').toList();
  final wsUri = uri
      .replaceFirst('http://', 'ws://')
      .replaceFirst('https://', 'wss://')
      .replaceFirst(RegExp(r'/?$'), '/ws');

  final socket = await WebSocket.connect(wsUri);
  var id = 0;
  final pending = <int, Completer<Map<String, Object?>>>{};
  socket.listen((message) {
    final decoded = jsonDecode(message as String) as Map<String, Object?>;
    final requestId = decoded['id'];
    if (requestId is! int) {
      return;
    }
    final completer = pending.remove(requestId);
    if (completer == null) {
      return;
    }
    if (decoded['error'] != null) {
      completer.completeError(Exception('${decoded['error']}'));
    } else {
      completer.complete(
        (decoded['result'] as Map?)?.cast<String, Object?>() ?? {},
      );
    }
  });

  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    final requestId = ++id;
    final completer = Completer<Map<String, Object?>>();
    pending[requestId] = completer;
    socket.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': requestId,
      'method': method,
      'params': params,
    }));
    return completer.future.timeout(const Duration(seconds: 30));
  }

  final vm = await call('getVM');
  final isolates = (vm['isolates'] as List?) ?? const [];
  if (isolates.isEmpty) {
    stderr.writeln('没有找到 isolate');
    exit(1);
  }
  final isolateId = (isolates.first as Map)['id'] as String;

  final result = await call(
    useRenderTree ? 'ext.flutter.debugDumpRenderTree' : 'ext.flutter.debugDumpApp',
    {
    'isolateId': isolateId,
    },
  );
  final tree = (result['data'] as String?) ?? '';
  await socket.close();

  if (keywords.isEmpty) {
    print(tree);
    return;
  }
  final lines = const LineSplitter().convert(tree);
  for (final keyword in keywords) {
    final hits = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains(keyword)) {
        hits.add('  L$i: ${lines[i].trim()}');
      }
    }
    print(
      hits.isEmpty
          ? '✗ 未找到 "$keyword"'
          : '✓ 找到 "$keyword"（${hits.length} 处）\n${hits.take(5).join('\n')}',
    );
  }
  print('（控件树共 ${lines.length} 行）');
}
