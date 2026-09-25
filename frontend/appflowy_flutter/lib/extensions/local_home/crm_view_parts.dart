import 'package:app_crm_biz/app_crm_biz.dart';
import 'package:appflowy/extensions/local_home/crm_field_inputs.dart';
import 'package:appflowy/extensions/local_home/mobile_ui_kit.dart';
import 'package:flutter/material.dart';

/// CRM 列表/卡片上用的小构件与格式化（客户卡四信息位、等级徽标、逾期红点…）。
///
/// 抽出来是因为同一套信息会同时出现在**列表卡片**（首页）和**详情头卡**里，
/// 两处必须长得一样；颜色一律走 `Theme.of(context).colorScheme`，跟主题/暗色。
/// 客户等级徽标（A / B / C，来自预置字段「客户等级」）。
class CrmLevelBadge extends StatelessWidget {
  const CrmLevelBadge({super.key, required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground) = switch (letter) {
      'A' => (scheme.primaryContainer, scheme.onPrimaryContainer),
      'B' => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        letter,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 关键日期逾期的小红点（挂在名称后面，不占一行）。
class CrmOverdueDot extends StatelessWidget {
  const CrmOverdueDot({super.key, this.tooltip});

  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        shape: BoxShape.circle,
      ),
    );
    return tooltip == null ? dot : Tooltip(message: tooltip!, child: dot);
  }
}

/// 「最近互动」一句话：`3 天前 · 电话` / `今天 · 拜访` / `暂无跟进`。
String formatCrmInteraction(CrmEvent? event, {DateTime? now}) {
  if (event == null) {
    return '暂无跟进';
  }
  return '${formatCrmRelativeDay(event.eventTime, now: now)} · ${event.kind}';
}

/// 相对日期：今天 / 昨天 / N 天前 / 超过 30 天显示 `2026-08-12`。
String formatCrmRelativeDay(DateTime day, {DateTime? now}) {
  final today = dateOnly(now ?? DateTime.now());
  final target = dateOnly(day);
  final days = today.difference(target).inDays;
  if (days <= 0) {
    return '今天';
  }
  if (days == 1) {
    return '昨天';
  }
  if (days <= 30) {
    return '$days 天前';
  }
  return formatCrmDate(target);
}

/// 金额紧凑显示：`1,234` / `1.2万` / `128万`（列表里不用撑爆一行）。
String formatCrmMoney(double value) {
  if (value >= 10000) {
    final wan = value / 10000;
    final text = wan.toStringAsFixed(wan >= 100 ? 0 : 1);
    // 6.0 万 → 6 万（整数不留小数尾巴）
    return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}万';
  }
  final text = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(text[i]);
  }
  return buffer.toString();
}

/// 「今天该跟进」横条（设计定稿第 2 节）：最多 3 条，点开、点完成、左滑推迟。
///
/// 命中的原因用左侧小圆点区分：手动 ⭐（主色）/ 关键日期（错误色）/ 久未跟进（灰色）。
class CrmFollowUpBar extends StatelessWidget {
  const CrmFollowUpBar({
    super.key,
    required this.items,
    required this.onOpen,
    required this.onComplete,
    required this.onPostpone,
  });

  final List<CrmFollowUp> items;
  final Future<void> Function(CrmEntity entity) onOpen;
  final Future<void> Function(CrmFollowUp item) onComplete;
  final Future<void> Function(CrmFollowUp item) onPostpone;

  /// 横条里最多并排显示几条（其余收起，点"还有 N 条"展开）。
  static const int maxVisible = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final visible = items.take(maxVisible).toList();
    final rest = items.length - visible.length;
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '今天该跟进 ${items.length}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (rest > 0)
                GestureDetector(
                  onTap: () => showCrmFollowUpSheet(
                    context: context,
                    items: items,
                    onOpen: onOpen,
                    onComplete: onComplete,
                    onPostpone: onPostpone,
                  ),
                  child: Text(
                    '还有 $rest 条 ›',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 每条一行（标题 + 原因两行）——中文长名字在"三列并排"里截得太狠，
          // 换成一列三条后标题能看全；左滑＝推迟 3 天。
          for (final item in visible) ...[
            Dismissible(
              key: ValueKey('followup-${item.entity.id}'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(Mob.radiusSmall + 2),
                ),
                child: Text(
                  '推迟 3 天',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              onDismissed: (_) => onPostpone(item),
              child: _FollowUpRow(
                item: item,
                onTap: () => onOpen(item.entity),
                onComplete: () => onComplete(item),
              ),
            ),
            if (item != visible.last) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _FollowUpRow extends StatelessWidget {
  const _FollowUpRow({
    required this.item,
    required this.onTap,
    required this.onComplete,
  });

  final CrmFollowUp item;
  final VoidCallback onTap;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reasonColor = switch (item.reason) {
      CrmFollowUpReason.manual => scheme.primary,
      CrmFollowUpReason.overdue => scheme.error,
      CrmFollowUpReason.stale => scheme.outline,
    };
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(Mob.radiusSmall + 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(Mob.radiusSmall + 2),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: reasonColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.entity.title.isEmpty
                          ? CrmEntityType.label(item.entity.type)
                          : item.entity.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${CrmEntityType.label(item.entity.type)} · ${item.detail}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: reasonColor == scheme.outline
                            ? scheme.onSurfaceVariant
                            : reasonColor,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '今天完成',
                icon: const Icon(Icons.check_circle_outline, size: 20),
                color: scheme.outline,
                visualDensity: VisualDensity.compact,
                onPressed: onComplete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「还有 N 条」展开的完整清单（底部弹层）。
Future<void> showCrmFollowUpSheet({
  required BuildContext context,
  required List<CrmFollowUp> items,
  required Future<void> Function(CrmEntity entity) onOpen,
  required Future<void> Function(CrmFollowUp item) onComplete,
  required Future<void> Function(CrmFollowUp item) onPostpone,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(
                '今天该跟进 ${items.length}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '点开看详情；✓ 表示今天处理完了，推迟＝3 天后再提醒',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              for (final item in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await onOpen(item.entity);
                  },
                  title: Text(
                    item.entity.title.isEmpty
                        ? CrmEntityType.label(item.entity.type)
                        : item.entity.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${CrmEntityType.label(item.entity.type)} · ${item.reason.label} · ${item.detail}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '今天完成',
                        icon: const Icon(Icons.check_circle_outline),
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          await onComplete(item);
                        },
                      ),
                      IconButton(
                        tooltip: '推迟 3 天',
                        icon: const Icon(Icons.schedule),
                        onPressed: () async {
                          Navigator.of(sheetContext).pop();
                          await onPostpone(item);
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
