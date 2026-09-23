/// 一天的日记元数据（业务库记录，正文在内核文档里）。
class DiaryEntry {
  const DiaryEntry({
    required this.dateKey,
    this.mood = '',
    this.weather = '',
    this.location = '',
    this.documentId,
    required this.updatedAt,
  });

  /// 日期键：`yyyy-MM-dd`（本地时区）。
  final String dateKey;

  /// 心情 emoji（见 `kDiaryMoods`）。
  final String mood;

  /// 天气 emoji（见 `kDiaryWeathers`）。
  final String weather;
  final String location;

  /// 对应的内核日记文档 view id（首次打开该日时自动创建）。
  final String? documentId;
  final DateTime updatedAt;

  bool get hasDocument => documentId != null && documentId!.isNotEmpty;

  DiaryEntry copyWith({
    String? mood,
    String? weather,
    String? location,
    String? documentId,
    DateTime? updatedAt,
  }) {
    return DiaryEntry(
      dateKey: dateKey,
      mood: mood ?? this.mood,
      weather: weather ?? this.weather,
      location: location ?? this.location,
      documentId: documentId ?? this.documentId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 日期键工具：本地时区 `yyyy-MM-dd`。
  static String keyOf(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  static DateTime? parseKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) {
      return null;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day);
  }
}
