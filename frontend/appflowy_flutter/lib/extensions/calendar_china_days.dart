/// 中国节假日 / 调休数据（2026）。
///
/// 数据来源：参考项目 `E:\Dev\moodiaryCRM\assets\calendar\china_holidays_2026.json`
/// （原始出处 timor.tech/api/holiday）。这里直接内联成常量表，
/// 免去资源打包与解析开销 —— 每年更新一次即可（换年份时替换 [days2026]）。
library;

/// 某一天的节假日信息。
class ChinaDay {
  const ChinaDay({required this.name, required this.isHoliday});

  final String name;

  /// true = 放假；false = 调休上班。
  final bool isHoliday;
}

/// `yyyy-MM-dd` → 节假日信息。
const Map<String, ChinaDay> chinaDays2026 = {
  '2026-01-01': ChinaDay(name: '元旦', isHoliday: true),
  '2026-01-02': ChinaDay(name: '元旦', isHoliday: true),
  '2026-01-03': ChinaDay(name: '元旦', isHoliday: true),
  '2026-01-04': ChinaDay(name: '元旦后补班', isHoliday: false),
  '2026-02-14': ChinaDay(name: '春节前补班', isHoliday: false),
  '2026-02-15': ChinaDay(name: '春节', isHoliday: true),
  '2026-02-16': ChinaDay(name: '除夕', isHoliday: true),
  '2026-02-17': ChinaDay(name: '初一', isHoliday: true),
  '2026-02-18': ChinaDay(name: '初二', isHoliday: true),
  '2026-02-19': ChinaDay(name: '初三', isHoliday: true),
  '2026-02-20': ChinaDay(name: '初四', isHoliday: true),
  '2026-02-21': ChinaDay(name: '初五', isHoliday: true),
  '2026-02-22': ChinaDay(name: '初六', isHoliday: true),
  '2026-02-23': ChinaDay(name: '初七', isHoliday: true),
  '2026-02-28': ChinaDay(name: '春节后补班', isHoliday: false),
  '2026-04-04': ChinaDay(name: '清明节', isHoliday: true),
  '2026-04-05': ChinaDay(name: '清明节', isHoliday: true),
  '2026-04-06': ChinaDay(name: '清明节', isHoliday: true),
  '2026-05-01': ChinaDay(name: '劳动节', isHoliday: true),
  '2026-05-02': ChinaDay(name: '劳动节', isHoliday: true),
  '2026-05-03': ChinaDay(name: '劳动节', isHoliday: true),
  '2026-05-04': ChinaDay(name: '劳动节', isHoliday: true),
  '2026-05-05': ChinaDay(name: '劳动节', isHoliday: true),
  '2026-05-09': ChinaDay(name: '劳动节后补班', isHoliday: false),
  '2026-06-19': ChinaDay(name: '端午节', isHoliday: true),
  '2026-06-20': ChinaDay(name: '端午节', isHoliday: true),
  '2026-06-21': ChinaDay(name: '端午节', isHoliday: true),
  '2026-09-20': ChinaDay(name: '中秋节前补班', isHoliday: false),
  '2026-09-25': ChinaDay(name: '中秋节', isHoliday: true),
  '2026-09-26': ChinaDay(name: '中秋节', isHoliday: true),
  '2026-09-27': ChinaDay(name: '中秋节', isHoliday: true),
  '2026-10-01': ChinaDay(name: '国庆节', isHoliday: true),
  '2026-10-02': ChinaDay(name: '国庆节', isHoliday: true),
  '2026-10-03': ChinaDay(name: '国庆节', isHoliday: true),
  '2026-10-04': ChinaDay(name: '国庆节', isHoliday: true),
  '2026-10-05': ChinaDay(name: '国庆节', isHoliday: true),
  '2026-10-06': ChinaDay(name: '国庆节', isHoliday: true),
  '2026-10-07': ChinaDay(name: '国庆节', isHoliday: true),
  '2026-10-10': ChinaDay(name: '国庆节后补班', isHoliday: false),
};

/// 查某天是不是节假日/调休（`key` 用 `yyyy-MM-dd`）。
ChinaDay? chinaDayOf(String dateKey) => chinaDays2026[dateKey];

/// 国庆等长假按年份兜底（没有数据时返回 null）。
ChinaDay? chinaDayOfDate(DateTime date) =>
    chinaDayOf('${date.year}-${_two(date.month)}-${_two(date.day)}');

String _two(int value) => value.toString().padLeft(2, '0');
