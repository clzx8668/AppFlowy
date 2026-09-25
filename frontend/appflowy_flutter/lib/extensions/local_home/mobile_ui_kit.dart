import 'package:flutter/material.dart';

/// 手机端设计令牌（对齐 `E:\Dev\moodiaryCRM` 的手机端 UI 语言）。
///
/// 只放"尺寸/圆角/间距"这类常量与小构件，具体页面各自组装；
/// 颜色一律走 `Theme.of(context).colorScheme`，不写死色值，方便跟随主题与暗色模式。
class Mob {
  const Mob._();

  /// 圆角：小 8 / 中 12 / 大 16（与参考项目一致）
  static const double radiusSmall = 8;
  static const double radiusMedium = 12;
  static const double radiusLarge = 16;

  /// 底部导航高度（不含安全区）
  static const double navBarHeight = 56;

  /// FAB 尺寸与上滑展开菜单的尺寸
  static const double fabSize = 56;
  static const double fabActionHeight = 46;
  static const double fabSpacing = 8;

  /// 列表卡片：最小高度与内边距
  static const double cardMinHeight = 96;
  static const EdgeInsets cardPadding = EdgeInsets.all(12);
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(12, 4, 12, 96);
}

/// 手机端列表卡片：`Card.filled` + 圆角 12 + 可点。
class MobCard extends StatelessWidget {
  const MobCard({super.key, required this.child, this.onTap, this.onLongPress});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.filled(
      color: theme.colorScheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Mob.radiusMedium),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Mob.radiusMedium),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(padding: Mob.cardPadding, child: child),
      ),
    );
  }
}

/// 圆形图标按钮（底栏"回到顶部"、FAB 展开项用）。
class MobRoundIconButton extends StatelessWidget {
  const MobRoundIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final button = Material(
      color: theme.colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(Mob.radiusLarge),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(Mob.radiusLarge),
        onTap: onTap,
        child: SizedBox(
          width: Mob.fabSize,
          height: Mob.fabSize,
          child: Icon(
            icon,
            color: theme.colorScheme.onTertiaryContainer,
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// FAB 展开后的胶囊按钮（带文字标签）。
class MobPillAction extends StatelessWidget {
  const MobPillAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(Mob.radiusSmall),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(Mob.radiusSmall),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 手机端分类/标签筛选 chip。
class MobFilterChip extends StatelessWidget {
  const MobFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        label: Text(
          leading == null ? label : '$leading $label',
          style: theme.textTheme.labelMedium,
        ),
      ),
    );
  }
}

/// 手机端底部导航（对齐参考项目：高 56 + 安全区，图标 24、标签在下方，
/// 顶边 0.5px 细线，选中用 `onSecondaryContainer` 加粗）。
class MobBottomBarItem {
  const MobBottomBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class MobBottomBar extends StatelessWidget {
  const MobBottomBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<MobBottomBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: Mob.navBarHeight + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(
          top: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(Mob.radiusLarge),
                onTap: () => onTap(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      i == currentIndex
                          ? items[i].selectedIcon
                          : items[i].icon,
                      size: 24,
                      color: i == currentIndex
                          ? colorScheme.onSecondaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      items[i].label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: i == currentIndex
                            ? colorScheme.onSecondaryContainer
                            : colorScheme.onSurfaceVariant,
                        fontWeight: i == currentIndex ? FontWeight.w600 : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 手机端 FAB（对齐参考项目）：点击＝速记（新建记录），上滑＝展开菜单。
///
/// 展开时主按钮旋转 135°，菜单项为"回到顶部 / 新建日记"这两个胶囊按钮。
/// （参考项目的长按是"直达语音录音"，我们暂未接入离线转写，因此长按不占用手势。）
class MobRecordsFab extends StatelessWidget {
  const MobRecordsFab({
    super.key,
    required this.expanded,
    required this.onTapMain,
    required this.onSwipeUp,
    required this.onCollapse,
    this.onNewDiary,
    this.onToTop,
  });

  final bool expanded;
  final VoidCallback onTapMain;
  final VoidCallback onSwipeUp;
  final VoidCallback onCollapse;
  final VoidCallback? onNewDiary;
  final VoidCallback? onToTop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <Widget>[
      if (onToTop != null)
        MobRoundIconButton(
          icon: Icons.arrow_upward,
          tooltip: '回到顶部',
          onTap: onToTop!,
        ),
      if (onNewDiary != null)
        MobPillAction(
          label: '新建日记',
          icon: Icons.edit_note,
          onTap: onNewDiary!,
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.bottomRight,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(bottom: Mob.fabSpacing),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final item in items) ...[
                        item,
                        const SizedBox(height: Mob.fabSpacing),
                      ],
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        GestureDetector(
          onTap: expanded ? onCollapse : onTapMain,
          onVerticalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -100) {
              onSwipeUp();
            } else if (velocity > 100 && expanded) {
              onCollapse();
            }
          },
          child: Material(
            color: expanded
                ? theme.colorScheme.surfaceContainerHighest
                // 用 primary/onPrimary：AppFlowy 主题下 primaryContainer 偏浅，
                // 加号几乎看不见；这里以"看得清"优先，形状仍与参考项目一致。
                : theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(Mob.radiusLarge),
            elevation: 2,
            child: SizedBox(
              width: Mob.fabSize,
              height: Mob.fabSize,
              child: AnimatedRotation(
                turns: expanded ? 3 / 8 : 0, // 135°
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  Icons.add,
                  color: expanded
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onPrimary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
