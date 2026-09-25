import 'package:shared_preferences/shared_preferences.dart';

/// 手机端偏好（排序方式 / 视图形态 / 默认新建落点），存 `shared_preferences`。
///
/// 为什么单独放一个文件：这些偏好与页面逻辑无关，集中一处便于后续继续加
/// （比如默认日历视图、默认展开折叠条等）。
class MobPrefs {
  const MobPrefs._();

  static const String _sortKey = 'records_sort';
  static const String _gridKey = 'records_grid';

  static SharedPreferences? _prefs;

  static Future<SharedPreferences?> _instance() async {
    if (_prefs != null) {
      return _prefs;
    }
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
    return _prefs;
  }

  /// 排序方式（存的枚举下标；读取失败返回 [fallback]）。
  static Future<int?> readSortIndex() async {
    final prefs = await _instance();
    return prefs?.getInt(_sortKey);
  }

  static Future<void> writeSortIndex(int index) async {
    final prefs = await _instance();
    await prefs?.setInt(_sortKey, index);
  }

  static Future<bool?> readGridMode() async {
    final prefs = await _instance();
    return prefs?.getBool(_gridKey);
  }

  static Future<void> writeGridMode(bool grid) async {
    final prefs = await _instance();
    await prefs?.setBool(_gridKey, grid);
  }
}
