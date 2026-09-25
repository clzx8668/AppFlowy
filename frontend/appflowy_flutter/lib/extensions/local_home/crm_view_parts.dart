import 'package:app_crm_biz/app_crm_biz.dart';
import 'package:appflowy/extensions/local_home/crm_field_inputs.dart';
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
