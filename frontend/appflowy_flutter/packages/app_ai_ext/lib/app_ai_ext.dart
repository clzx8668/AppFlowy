/// AI 扩展模块（骨架）
///
/// 蓝图定位：AI 可无限迭代的个人智能记忆系统；本地优先、可自选模型。
///
/// 复用（**不重写 AI**）：
/// - 抽象层：`lib/ai/service/appflowy_ai_service.dart` 的 `AIRepository`（流式补全、内置提示词）
/// - 注册点：`lib/startup/deps_resolver.dart` 的 `getIt.registerFactory<AIRepository>(...)`
///   → 本包提供自己的实现即可整体替换/包装上游 `AppFlowyAIService`
/// - 已有 UI：`lib/ai/widgets/**`（提示词输入、模型选择）、`lib/plugins/ai_chat/**`（AI 聊天页）
/// - 本地模型：内核 `flowy-ai` 已支持 Ollama，可完全离线
///
/// 自研：
/// - 面向上层价值的编排：闪念/日记自动摘要、自动标签、周期回顾、基于个人记忆的问答
/// - 提示词模板与模型路由策略（本地优先，云端可选）
library app_ai_ext;

/// 模块标识，用于日志与路由前缀。
const String kAppAiExtPackage = 'app_ai_ext';

/// AI 扩展对外提供的高层能力（骨架），内核调用一律走 `AIRepository`。
abstract interface class MemoryAiService {
  /// 对一段闪念/日记做摘要与标签，返回可写入元数据的结果。
  Future<AiDigestResult> digest(String text);

  /// 周期回顾（周/月），输入区间内的时间日记与闪念。
  Future<String> review(DateTime start, DateTime end);
}

/// 摘要/标签结果（骨架）。
class AiDigestResult {
  const AiDigestResult({required this.summary, this.tags = const []});

  final String summary;
  final List<String> tags;
}
