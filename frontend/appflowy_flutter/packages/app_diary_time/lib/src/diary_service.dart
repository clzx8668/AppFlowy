import 'diary_entry.dart';
import 'diary_repository.dart';

/// 日记文档网关：负责在内核里创建/定位某天的日记文档。
///
/// 由 App 侧注入实现（依赖倒置），扩展包不直接依赖内核与编辑器。
abstract interface class DiaryDocumentGateway {
  /// 确保某天的日记文档存在，返回 view id。
  Future<String> ensureDailyDocument({
    required DateTime date,
    required String title,
  });
}

/// 日记服务：打开/创建某天日记、维护生活元数据、按月查询标记。
class DiaryService {
  DiaryService({
    required DiaryRepository repository,
    required DiaryDocumentGateway documentGateway,
  })  : _repository = repository,
        _documentGateway = documentGateway;

  final DiaryRepository _repository;
  final DiaryDocumentGateway _documentGateway;

  /// 打开（必要时创建）某天的日记：没有文档就建一篇（标题=日期），并回写业务库。
  Future<DiaryEntry> openOrCreate(DateTime date) async {
    final dateKey = DiaryEntry.keyOf(date);
    final existing = await _repository.entryOf(dateKey);
    if (existing?.hasDocument ?? false) {
      return existing!;
    }
    final documentId = await _documentGateway.ensureDailyDocument(
      date: date,
      title: dateKey,
    );
    final entry = (existing ??
            DiaryEntry(
              dateKey: dateKey,
              updatedAt: DateTime.now(),
            ))
        .copyWith(documentId: documentId, updatedAt: DateTime.now());
    await _repository.upsert(entry);
    return entry;
  }

  Future<DiaryEntry> setMood(DateTime date, String mood) {
    return _patch(date, (entry) => entry.copyWith(mood: mood));
  }

  Future<DiaryEntry> setWeather(DateTime date, String weather) {
    return _patch(date, (entry) => entry.copyWith(weather: weather));
  }

  Future<DiaryEntry> setLocation(DateTime date, String location) {
    return _patch(date, (entry) => entry.copyWith(location: location));
  }

  /// 某月的全部日记（用于月历标记）。
  Future<List<DiaryEntry>> entriesOfMonth(DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0);
    return _repository.entriesBetween(
      DiaryEntry.keyOf(start),
      DiaryEntry.keyOf(end),
    );
  }

  Future<DiaryEntry> _patch(
    DateTime date,
    DiaryEntry Function(DiaryEntry entry) patch,
  ) async {
    final dateKey = DiaryEntry.keyOf(date);
    final existing = await _repository.entryOf(dateKey) ??
        DiaryEntry(dateKey: dateKey, updatedAt: DateTime.now());
    final updated = patch(existing).copyWith(updatedAt: DateTime.now());
    await _repository.upsert(updated);
    return updated;
  }
}
