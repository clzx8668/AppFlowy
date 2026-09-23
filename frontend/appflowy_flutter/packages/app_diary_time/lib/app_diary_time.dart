/// 时间日记模块 —— 月历回溯 + 每日日记 + 生活元数据。
///
/// 设计（见 doc/现有模块复用与扩展分析.md）：
/// - **每日日记 = 内核 Document**（标题为日期，如 `2026-09-24`），默认落在「笔记」容器下，
///   直接获得块编辑、双链、搜索、回收站能力；
/// - **生活元数据**（心情/天气/位置）存独立业务库 `diary_entries`，通过 view id 与日记文档关联；
/// - 月历由自研页面渲染（iOS18 风格），读业务库标记"哪天写过日记 + 心情色点"。
library app_diary_time;

export 'src/diary_entry.dart';
export 'src/diary_repository.dart';
export 'src/diary_service.dart';

/// 模块标识。
const String kAppDiaryTimePackage = 'app_diary_time';

/// 心情候选（emoji + 名称，用于选择器与月历色点）。
const List<(String emoji, String label)> kDiaryMoods = [
  ('😄', '很好'),
  ('🙂', '不错'),
  ('😐', '一般'),
  ('😔', '低落'),
  ('😡', '生气'),
];

/// 天气候选。
const List<(String emoji, String label)> kDiaryWeathers = [
  ('☀️', '晴'),
  ('🌤️', '多云'),
  ('☁️', '阴'),
  ('🌧️', '雨'),
  ('❄️', '雪'),
];
