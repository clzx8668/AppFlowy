import 'package:appflowy/env/local_first.dart';
import 'package:scaled_app/scaled_app.dart';

import 'startup/startup.dart';

Future<void> main() async {
  ScaledWidgetsFlutterBinding.ensureInitialized(
    scaleFactor: (_) => 1.0,
  );

  // 二次开发：默认以本地（匿名）模式启动。isAnon 为 true 时不会请求 AppFlowy Cloud，
  // 而是直接使用/创建一个本地用户，数据只保存在本机。
  await runAppFlowy(isAnon: kLocalFirstMode);
}
