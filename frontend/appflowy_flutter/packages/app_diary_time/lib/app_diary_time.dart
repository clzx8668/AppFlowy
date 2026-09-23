/// 时间日记模块（骨架）
///
/// 蓝图定位：时间日记体系、日历回溯、生活元数据块（心情/天气/位置/录音/倒计时）。
///
/// 复用：
/// - 正文：每天一篇普通 Document（标题即日期），沿用内核块能力与双链
/// - `DateService.queryDate`：自然语言日期解析
/// - 内核按日期检索/排序能力（用于时间线回溯）
///
/// 自研：
/// - 极简月历（对标 Bloomnote，不暴露上游原生 database 日历视图）
/// - 每日日记页（大留白纯画布 + 生活元数据块）
/// - 时间线回溯、心情/天气/位置统计
///
/// 自定义生活块：在本包内实现 `BlockComponentBuilder`（节点类型如 `mood_block`），
/// 由 App 层在 `editor_configuration.dart` 的 builder map 上挂载（唯一的一行适配）。
library app_diary_time;

/// 模块标识，用于日志与路由前缀。
const String kAppDiaryTimePackage = 'app_diary_time';

/// 日记条目元数据（骨架）：正文仍在内核文档里，这里只存索引与生活元数据。
class DiaryEntryMeta {
  const DiaryEntryMeta({
    required this.date,
    this.mood,
    this.weather,
    this.location,
    this.documentId,
  });

  /// 归属日期（本地时区，取日粒度）。
  final DateTime date;
  final String? mood;
  final String? weather;
  final String? location;

  /// 对应的内核文档（view）id。
  final String? documentId;
}

/// 日记服务契约：打开/创建某天的日记。
abstract interface class DiaryService {
  Future<DiaryEntryMeta> openOrCreateDailyNote(DateTime date);

  /// 按日区间拉取日记索引（用于月历标记与时间线）。
  Future<List<DiaryEntryMeta>> entriesBetween(DateTime start, DateTime end);
}
