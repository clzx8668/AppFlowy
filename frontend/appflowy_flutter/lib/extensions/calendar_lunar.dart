import 'package:lunar/lunar.dart';

/// 一天的农历信息（农历日、节气、节日）。
///
/// 依赖 `lunar` 包（6tail，纯 Dart，无原生依赖），用于日历格里显示
/// 「初三 / 十五 / 中秋 / 立秋」这类中文日历必备信息。
class LunarInfo {
  const LunarInfo({
    required this.lunarDay,
    required this.lunarMonth,
    required this.jieQi,
    required this.festival,
  });

  /// 农历日，如「初一」「十五」。
  final String lunarDay;

  /// 农历月，如「正」「腊」。
  final String lunarMonth;

  /// 节气（当天恰好是节气时非空）。
  final String jieQi;

  /// 节日（公历或农历，取第一个）。
  final String festival;

  /// 日历格下方显示的文字：节日 > 节气 > 农历日（初一/十五也直接显示农历日）。
  String get shortLabel {
    if (festival.isNotEmpty) {
      return festival.length > 3 ? festival.substring(0, 3) : festival;
    }
    if (jieQi.isNotEmpty) {
      return jieQi.length > 3 ? jieQi.substring(0, 3) : jieQi;
    }
    return lunarDay;
  }

  /// 是否是"值得强调"的日子（节日/节气/初一/十五）。
  bool get isHighlighted =>
      festival.isNotEmpty ||
      jieQi.isNotEmpty ||
      lunarDay == '初一' ||
      lunarDay == '十五';

  String get fullText => '农历$lunarMonth月$lunarDay'
      '${jieQi.isEmpty ? '' : ' · $jieQi'}'
      '${festival.isEmpty ? '' : ' · $festival'}';
}

LunarInfo lunarInfoOf(DateTime date) {
  try {
    final lunar = Lunar.fromDate(date);
    final solar = Solar.fromDate(date);
    final festivals = [
      ...solar.getFestivals(),
      ...lunar.getFestivals(),
    ]..removeWhere((f) => f.isEmpty);
    return LunarInfo(
      lunarDay: lunar.getDayInChinese(),
      lunarMonth: lunar.getMonthInChinese(),
      jieQi: lunar.getJieQi(),
      festival: festivals.isEmpty ? '' : festivals.first,
    );
  } catch (_) {
    return const LunarInfo(
      lunarDay: '',
      lunarMonth: '',
      jieQi: '',
      festival: '',
    );
  }
}
