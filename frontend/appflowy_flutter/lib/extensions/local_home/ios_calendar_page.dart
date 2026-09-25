import 'dart:async';

import 'package:app_diary_time/app_diary_time.dart';
import 'package:appflowy/extensions/diary_entry.dart';
import 'package:appflowy/extensions/flash_note_entry.dart';
import 'package:appflowy/extensions/local_home/mobile_ui_kit.dart';
import 'package:appflowy/extensions/timeline_entry.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';

/// iOS 风格日历页（自建，贴合本项目架构）。
///
/// 与参考项目无关：数据全部来自我们自己的三层
/// —— 内核页面树（当天记录）、日记业务库（心情/天气/地点）、时间线数据库（时间轴）。
///
/// 交互：
/// - 上半部分是 iOS 风格月历（大标题 + 圆角日期 + 内容圆点 + 今天/选中态）；
/// - 下半部分是**当天内容**：心情/天气/地点、当天日记入口、当天记录列表；
/// - 顶部可切到「时间线」视图（最近记录 + 那年今日 + 心情统计）。
class IosCalendarPage extends StatefulWidget {
  const IosCalendarPage({
    super.key,
    required this.workspaceId,
    required this.userId,
    this.timelineParentViewId,
  });

  final String workspaceId;
  final Int64 userId;

  /// 「时间线」数据库页所在的父容器（日历分类容器）id；为空则隐藏时间轴入口。
  final String? timelineParentViewId;

  @override
  State<IosCalendarPage> createState() => _IosCalendarPageState();
}

class _IosCalendarPageState extends State<IosCalendarPage> {
  DiaryService? _service;
  bool _loading = true;

  late DateTime _month;
  late DateTime _selected;

  /// 0 = 月历，1 = 时间线
  int _segment = 0;

  Map<String, DiaryEntry> _entries = {};
  Map<String, int> _moodCounts = const {};
  List<DiaryEntry> _timeline = const [];
  List<DiaryEntry> _onThisDay = const [];

  /// 某天有哪些记录（来自内核页面树）
  Map<String, List<ViewPB>> _recordsByDay = {};

  @override
  void initState() {
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final service = await createDiaryService(
        workspaceId: widget.workspaceId,
        userId: widget.userId,
      );
      if (!mounted) {
        return;
      }
      setState(() => _service = service);
      await _reload();
    } catch (e) {
      Log.error('[日历] 初始化失败：$e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _reload() async {
    final service = _service;
    if (service == null) {
      return;
    }
    try {
      final entries = await service.entriesOfMonth(_month);
      final timeline = await service.timeline();
      final onThisDay = await service.onThisDay(_selected);
      final moodCounts = await service.moodCounts(month: _month);
      final recordsByDay = await _loadRecordsByDay();
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = {for (final entry in entries) entry.dateKey: entry};
        _timeline = timeline;
        _onThisDay = onThisDay;
        _moodCounts = moodCounts;
        _recordsByDay = recordsByDay;
        _loading = false;
      });
    } catch (e) {
      Log.error('[日历] 刷新失败：$e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// 把内核页面按"最后编辑/创建"的日期归类，供月历圆点与"当天记录"使用。
  Future<Map<String, List<ViewPB>>> _loadRecordsByDay() async {
    final result = await ViewBackendService.getAllViews();
    final views = result.toNullable()?.items ?? const <ViewPB>[];
    final byDay = <String, List<ViewPB>>{};
    const shellNames = {'闪念', '工作记录', '生活日记'};
    for (final view in views) {
      if (view.layout != ViewLayoutPB.Document) {
        continue;
      }
      if (view.extra.contains('af_container')) {
        continue;
      }
      if (shellNames.contains(view.name.trim())) {
        continue;
      }
      final timestamp = view.lastEdited == Int64.ZERO
          ? view.createTime
          : view.lastEdited;
      if (timestamp == Int64.ZERO) {
        continue;
      }
      final time = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt() * 1000);
      final key = DiaryEntry.keyOf(time);
      byDay.putIfAbsent(key, () => []).add(view);
    }
    for (final list in byDay.values) {
      list.sort((a, b) {
        final ta = a.lastEdited == Int64.ZERO ? a.createTime : a.lastEdited;
        final tb = b.lastEdited == Int64.ZERO ? b.createTime : b.lastEdited;
        return tb.compareTo(ta);
      });
    }
    return byDay;
  }

  // ------------------------------------------------------------------ 交互

  Future<void> _openDiary(DateTime date) async {
    final service = _service;
    if (service == null) {
      return;
    }
    try {
      final entry = await service.openOrCreate(date);
      await _reload();
      final documentId = entry.documentId;
      if (documentId != null && mounted) {
        await openDocumentByViewId(context, documentId);
        await _reload();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打开日记失败：$e')));
      }
    }
  }

  Future<void> _pickMoodOrWeather({required bool mood}) async {
    final service = _service;
    if (service == null) {
      return;
    }
    final options = mood ? kDiaryMoods : kDiaryWeathers;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mood ? '今天心情' : '今天天气',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final option in options)
                    ActionChip(
                      label: Text('${option.$1} ${option.$2}'),
                      onPressed: () => Navigator.of(sheetContext).pop(option.$1),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || selected.isEmpty) {
      return;
    }
    if (mood) {
      await service.setMood(_selected, selected);
    } else {
      await service.setWeather(_selected, selected);
    }
    await _reload();
  }

  Future<void> _editLocation() async {
    final service = _service;
    if (service == null) {
      return;
    }
    final controller = TextEditingController(
      text: _entries[DiaryEntry.keyOf(_selected)]?.location ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('地点'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如 济南 · 客户现场'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null) {
      return;
    }
    await service.setLocation(_selected, value);
    await _reload();
  }

  Future<void> _openTimelineGrid() async {
    var id = timelineViewId;
    final parentId = widget.timelineParentViewId;
    if (id == null && parentId != null && parentId.isNotEmpty) {
      id = await ensureTimelinePage(parentViewId: parentId);
    }
    if (id != null && mounted) {
      await openDocumentByViewId(context, id);
    }
  }

  // ------------------------------------------------------------------ 构建

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('日历'),
        actions: [
          TextButton(
            onPressed: () {
              final now = DateTime.now();
              setState(() {
                _month = DateTime(now.year, now.month);
                _selected = DateTime(now.year, now.month, now.day);
              });
              unawaited(_reload());
            },
            child: const Text('今天'),
          ),
          IconButton(
            tooltip: '时间轴',
            icon: const Icon(Icons.timeline_outlined),
            onPressed: () => unawaited(_openTimelineGrid()),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                _segmentControl(theme),
                const SizedBox(height: 12),
                if (_segment == 0) ...[
                  _monthHeader(theme),
                  const SizedBox(height: 8),
                  _weekHeader(theme),
                  const SizedBox(height: 4),
                  _monthGrid(theme),
                  const SizedBox(height: 20),
                  _daySection(theme),
                  const SizedBox(height: 20),
                  _moodStatsCard(theme),
                ] else ...[
                  _moodStatsCard(theme),
                  const SizedBox(height: 16),
                  _onThisDayCard(theme),
                  const SizedBox(height: 16),
                  _timelineCard(theme),
                ],
              ],
            ),
    );
  }

  Widget _segmentControl(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Mob.radiusMedium),
      ),
      child: Row(
        children: [
          _segmentItem(theme, 0, '月历', Icons.calendar_month_outlined),
          _segmentItem(theme, 1, '时间线', Icons.timeline_outlined),
        ],
      ),
    );
  }

  Widget _segmentItem(ThemeData theme, int index, String label, IconData icon) {
    final selected = _segment == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _segment = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(Mob.radiusSmall),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monthHeader(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '${_month.year}年${_month.month}月',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left),
          onPressed: () {
            setState(() => _month = DateTime(_month.year, _month.month - 1));
            unawaited(_reload());
          },
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right),
          onPressed: () {
            setState(() => _month = DateTime(_month.year, _month.month + 1));
            unawaited(_reload());
          },
        ),
      ],
    );
  }

  Widget _weekHeader(ThemeData theme) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: [
        for (final label in labels)
          Expanded(
            child: Center(
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _monthGrid(ThemeData theme) {
    final firstDay = DateTime(_month.year, _month.month);
    final leading = (firstDay.weekday - DateTime.monday) % 7;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final key = DiaryEntry.keyOf(date);
      final entry = _entries[key];
      final hasRecords = (_recordsByDay[key] ?? const []).isNotEmpty;
      cells.add(
        _dayCell(
          theme,
          date: date,
          isSelected: DiaryEntry.keyOf(_selected) == key,
          entry: entry,
          hasRecords: hasRecords,
        ),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: GridView.count(
        key: ValueKey('${_month.year}-${_month.month}'),
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 0.86,
        children: cells,
      ),
    );
  }

  Widget _dayCell(
    ThemeData theme, {
    required DateTime date,
    required bool isSelected,
    required DiaryEntry? entry,
    required bool hasRecords,
  }) {
    final now = DateTime.now();
    final isToday = DiaryEntry.keyOf(now) == DiaryEntry.keyOf(date);
    final dotColor = entry == null || entry.mood.isEmpty
        ? theme.colorScheme.primary
        : _moodColor(entry.mood, theme);
    return GestureDetector(
      onTap: () {
        setState(() => _selected = date);
        unawaited(_reload());
      },
      onDoubleTap: () => unawaited(_openDiary(date)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? theme.colorScheme.primary
                  : (isToday
                      ? theme.colorScheme.primaryContainer
                      : Colors.transparent),
            ),
            child: Text(
              '${date.day}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight:
                    isSelected || isToday ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (entry != null || hasRecords)
                  ? dotColor
                  : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _daySection(ThemeData theme) {
    final key = DiaryEntry.keyOf(_selected);
    final entry = _entries[key];
    final records = _recordsByDay[key] ?? const <ViewPB>[];
    return MobCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _friendlyDate(theme, _selected),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: Text(
                  entry == null || entry.mood.isEmpty ? '😊 记心情' : entry.mood,
                ),
                onPressed: () => unawaited(_pickMoodOrWeather(mood: true)),
              ),
              ActionChip(
                label: Text(
                  entry == null || entry.weather.isEmpty
                      ? '⛅ 记天气'
                      : entry.weather,
                ),
                onPressed: () => unawaited(_pickMoodOrWeather(mood: false)),
              ),
              ActionChip(
                avatar: const Icon(Icons.place_outlined, size: 16),
                label: Text(
                  entry == null || entry.location.isEmpty
                      ? '地点'
                      : entry.location,
                ),
                onPressed: () => unawaited(_editLocation()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: () => unawaited(_openDiary(_selected)),
              child: Text(
                (entry?.hasDocument ?? false) ? '打开当天日记' : '写今天的日记',
              ),
            ),
          ),
          if (records.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '当天记录 ${records.length}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 4),
            for (final view in records.take(20))
              InkWell(
                onTap: () => unawaited(openDocumentByViewId(context, view.id)),
                borderRadius: BorderRadius.circular(Mob.radiusSmall),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 14,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          view.name.trim().isEmpty ? '未命名页面' : view.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        _timeOfDay(view),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _moodStatsCard(ThemeData theme) {
    final total = _moodCounts.values.fold<int>(0, (sum, v) => sum + v);
    return MobCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '心情统计 · ${_month.year}年${_month.month}月',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (total == 0)
            Text(
              '本月还没有记录心情',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            )
          else
            for (final option in kDiaryMoodOptions)
              if ((_moodCounts[option.$1] ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Text(option.$1),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 40,
                        child: Text(
                          option.$2,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (_moodCounts[option.$1] ?? 0) / total,
                            minHeight: 8,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _moodColor(option.$1, theme),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_moodCounts[option.$1]} 天',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }

  Widget _onThisDayCard(ThemeData theme) {
    return MobCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '那年今日 · ${_selected.month}月${_selected.day}日',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (_onThisDay.isEmpty)
            Text(
              '往年今天还没有记录',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            )
          else
            for (final entry in _onThisDay) _entryRow(theme, entry),
        ],
      ),
    );
  }

  Widget _timelineCard(ThemeData theme) {
    return MobCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '时间线',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (_timeline.isEmpty)
            Text(
              '还没有日记，回去月历里写一篇吧',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            )
          else
            for (final entry in _timeline) _entryRow(theme, entry),
        ],
      ),
    );
  }

  Widget _entryRow(ThemeData theme, DiaryEntry entry) {
    final date = DiaryEntry.parseKey(entry.dateKey);
    final chips = [
      if (entry.mood.isNotEmpty) entry.mood,
      if (entry.weather.isNotEmpty) entry.weather,
      if (entry.location.isNotEmpty) '📍${entry.location}',
    ];
    return InkWell(
      onTap: () {
        final documentId = entry.documentId;
        if (documentId != null && documentId.isNotEmpty) {
          unawaited(openDocumentByViewId(context, documentId));
        } else if (date != null) {
          unawaited(_openDiary(date));
        }
      },
      borderRadius: BorderRadius.circular(Mob.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _moodColor(entry.mood, theme),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.dateKey, style: theme.textTheme.bodyMedium),
                  if (chips.isNotEmpty)
                    Text(
                      chips.join('  '),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  Color _moodColor(String mood, ThemeData theme) {
    switch (mood) {
      case '😄':
        return const Color(0xFF34C759);
      case '🙂':
        return const Color(0xFF30B0C7);
      case '😐':
        return const Color(0xFF8E8E93);
      case '😔':
        return const Color(0xFF5E5CE6);
      case '😡':
        return const Color(0xFFFF3B30);
      default:
        return theme.colorScheme.primary;
    }
  }

  String _friendlyDate(ThemeData theme, DateTime date) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '${date.year}年${date.month}月${date.day}日 '
        '周${weekdays[date.weekday - 1]}';
  }

  String _timeOfDay(ViewPB view) {
    final timestamp =
        view.lastEdited == Int64.ZERO ? view.createTime : view.lastEdited;
    if (timestamp == Int64.ZERO) {
      return '';
    }
    final time = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt() * 1000);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}';
  }
}
