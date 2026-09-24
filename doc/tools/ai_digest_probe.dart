// 本地摘要器验证脚本（只在开发机上跑，不属于产品代码）。
// 运行：
//   cd E:\Dev\AppFlowy
//   dart --packages=frontend/appflowy_flutter/.dart_tool/package_config.json \
//        doc/tools/ai_digest_probe.dart
import 'package:app_ai_ext/app_ai_ext.dart';

Future<void> main() async {
  const digester = LocalTextDigester();
  const text = '''
今天去客户现场做了膜池方案的汇报。客户现场反馈说膜池布置要遵守偶数排布，
单池宽度不能超过2.3米，长度不能超过12米，运输的时候要特别注意。
我们重新测算了成本，报价单里的膜池价格需要更新。
客户现场还提到希望下周一之前给一版新的报价单。
''';
  final result = await digester.digest(text);
  print('engine=${result.engine}');
  print('summary=${result.summary}');
  print('tags=${result.tags}');
}
