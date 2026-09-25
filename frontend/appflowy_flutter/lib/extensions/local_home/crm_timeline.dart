import 'package:app_crm_biz/app_crm_biz.dart';
import 'package:appflowy/extensions/local_home/crm_view_parts.dart';
import 'package:appflowy/extensions/local_home/mobile_ui_kit.dart';
import 'package:flutter/material.dart';

/// CRM 跟踪记录**按天分组的时间轴**（设计定稿第 3 节）。
///
/// 规矩：
/// - **人工记录**＝左侧竖线上的圆点 + 类型徽标（电话/拜访/会议/微信/邮件/备注）；
/// - **自动事件**（阶段流转、线索转项目）＝浅灰小字，**不占圆点**，混在同一天里；
/// - 顶部一行类型筛选 chips；
/// - 默认只展开**最近 3 组**（天），更早的「展开全部（还有 N 天）」。
class CrmEventTimeline extends StatefulWidget {
  const CrmEventTimeline({
    super.key,
    required this.events,
    required this.onDelete,
    required this.onOpenLinkedView,
  });

  /// 该实体的全部跟踪记录（按时间倒序）。
  final List<CrmEvent> events;
  final Future<void> Function(CrmEvent event) onDelete;
  final void Function(String viewId) onOpenLinkedView;

  /// 默认展开的天数（更早的折起来）。
  static const int defaultVisibleGroups = 3;

  /// 自动事件（不是人工写的跟进）：阶段流转 / 转项目。
  static const List<String> autoKinds = ['阶段', '转项目', '系统'];

  static bool isAuto(CrmEvent event) => autoKinds.contains(event.kind);

  @override
  State<CrmEventTimeline> createState() => _CrmEventTimelineState();
}

class _CrmEventTimelineState extends State<CrmEventTimeline> {
  static const String _allKinds = '全部';

  String _filter = _allKinds;
  bool _showAllGroups = false;

  List<CrmEvent> get _filtered => _filter == _allKinds
      ? widget.events
      : widget.events.where((e) => e.kind == _filter).toList();

  /// 按"天"分组（事件本身已按时间倒序，所以组内顺序也是倒序）。
  List<MapEntry<DateTime, List<CrmEvent>>> get _groups {
    final groups = <MapEntry<DateTime, List<CrmEvent>>>[];
    for (final event in _filtered) {
      final day = dateOnly(event.eventTime);
      if (groups.isNotEmpty && groups.last.key == day) {
        groups.last.value.add(event);
      } else {
        groups.add(MapEntry(day, [event]));
      }
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final groups = _groups;
    final visible = _showAllGroups
        ? groups
        : groups.take(CrmEventTimeline.defaultVisibleGroups).toList();
    final hidden = groups.length - visible.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final kind in [_allKinds, ...CrmEvent.kinds])
                MobFilterChip(
                  label: kind,
                  selected: _filter == kind,
                  onTap: () => setState(() {
                    _filter = kind;
                    _showAllGroups = false;
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (groups.isEmpty)
          Text(
            _filter == _allKinds ? '还没有跟踪记录，点右上角「记录跟进」' : '没有「$_filter」类型的记录',
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
          )
        else
          for (var i = 0; i < visible.length; i++) ...[
            _dayLabel(theme, visible[i].key),
            const SizedBox(height: 4),
            for (final event in visible[i].value)
              CrmEventTimeline.isAuto(event)
                  ? _autoEventRow(theme, event)
                  : _manualEventRow(theme, event),
            if (i != visible.length - 1) const SizedBox(height: 10),
          ],
        if (hidden > 0)
          TextButton.icon(
            onPressed: () => setState(() => _showAllGroups = true),
            icon: const Icon(Icons.unfold_more, size: 16),
            label: Text('展开全部（还有 $hidden 天）'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          )
        else if (_showAllGroups &&
            groups.length > CrmEventTimeline.defaultVisibleGroups)
          TextButton.icon(
            onPressed: () => setState(() => _showAllGroups = false),
            icon: const Icon(Icons.unfold_less, size: 16),
            label: const Text('只看最近 3 天'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
      ],
    );
  }

  Widget _dayLabel(ThemeData theme, DateTime day) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Text(
        formatCrmDayLabel(day),
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// 自动事件：浅灰小字，**不占圆点**。
  Widget _autoEventRow(ThemeData theme, CrmEvent event) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome, size: 11, color: scheme.outlineVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${_time(event.eventTime)} · ${event.content}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 人工记录：左侧竖线 + 圆点 + 类型徽标 + 内容。
  Widget _manualEventRow(ThemeData theme, CrmEvent event) {
    final scheme = theme.colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 16,
            child: Column(
              children: [
                const SizedBox(height: 5),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Container(width: 2, color: scheme.outlineVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _kindBadge(theme, event.kind),
                      const SizedBox(width: 6),
                      Text(
                        _time(event.eventTime),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(event.content, style: theme.textTheme.bodyMedium),
                  if (event.linkedViewId.isNotEmpty)
                    InkWell(
                      onTap: () => widget.onOpenLinkedView(event.linkedViewId),
                      child: Text(
                        '查看记录 ›',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '删除这条记录',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 15),
            onPressed: () => widget.onDelete(event),
          ),
        ],
      ),
    );
  }

  Widget _kindBadge(ThemeData theme, String kind) {
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _kindIcon(kind),
            size: 11,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 3),
          Text(
            kind,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  static String _time(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}';
  }

  static IconData _kindIcon(String kind) {
    switch (kind) {
      case '电话':
        return Icons.call_outlined;
      case '拜访':
        return Icons.directions_walk;
      case '会议':
        return Icons.groups_outlined;
      case '微信':
        return Icons.chat_bubble_outline;
      case '邮件':
        return Icons.mail_outline;
      case '阶段':
      case '转项目':
        return Icons.trending_up;
      default:
        return Icons.sticky_note_2_outlined;
    }
  }
}
