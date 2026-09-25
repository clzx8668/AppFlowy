import 'package:flutter/material.dart';

/// 线性滑动标签（自绘）：**左对齐**、可横向滚动、下划线指示器跟随滑动。
///
/// 为什么不用 Material 的 `TabBar`：Material 3 下滚动型 TabBar 会带起始偏移，
/// 视觉上像"居中"，且样式受主题影响；自绘可完全控制（记录页与 CRM 页共用）。
///
/// 用法：传入同一个 [TabController]（页面用 `TabBarView` 实现左右滑动切页），
/// 指示器监听 `controller.animation`，因此点击切换与滑动切页时下划线都连续跟随。
class MobSlidingTabs extends StatefulWidget {
  const MobSlidingTabs({
    super.key,
    required this.controller,
    required this.labels,
    this.height = 44,
    this.leftPadding = 12,
    this.horizontalItemPadding = 14,
  });

  final TabController controller;
  final List<String> labels;
  final double height;
  final double leftPadding;

  /// 每个标签左右各留多少内边距（决定点击区域宽度）。
  final double horizontalItemPadding;

  @override
  State<MobSlidingTabs> createState() => _MobSlidingTabsState();
}

class _MobSlidingTabsState extends State<MobSlidingTabs> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.animation?.addListener(_onTabChanged);
    widget.controller.addListener(_onTabChanged);
  }

  @override
  void didUpdateWidget(covariant MobSlidingTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.animation?.removeListener(_onTabChanged);
      oldWidget.controller.removeListener(_onTabChanged);
      widget.controller.animation?.addListener(_onTabChanged);
      widget.controller.addListener(_onTabChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.animation?.removeListener(_onTabChanged);
    widget.controller.removeListener(_onTabChanged);
    _scrollController.dispose();
    super.dispose();
  }

  /// 切换标签时把当前项滚进可视区（只在真切换时滚，避免滑动过程中抖动）。
  void _onTabChanged() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final index = widget.controller.index;
    final widths = _measureWidths();
    if (index <= 0 || index >= widths.length) {
      return;
    }
    final offsetBefore =
        widths.take(index).fold<double>(0, (sum, w) => sum + w);
    final max = _scrollController.position.maxScrollExtent;
    final target = (offsetBefore - 24).clamp(0.0, max);
    if ((_scrollController.offset - target).abs() < 8) {
      return;
    }
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  /// 每个标签的整格宽度 = 文字宽 + 左右内边距。
  List<double> _measureWidths() {
    final style = widget._labelStyle();
    return [
      for (final label in widget.labels)
        (TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout())
            .width +
            widget.horizontalItemPadding * 2,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widths = _measureWidths();
    if (widths.isEmpty) {
      return const SizedBox.shrink();
    }
    final totalWidth = widths.fold<double>(0, (sum, w) => sum + w);

    final underlineWidths = [
      for (final w in widths) (w - widget.horizontalItemPadding * 2),
    ];

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final needsScroll =
              totalWidth + widget.leftPadding > constraints.maxWidth;
          final strip = SizedBox(
            width: needsScroll
                ? totalWidth + widget.leftPadding
                : constraints.maxWidth,
            height: widget.height,
            child: Stack(
              children: [
                Row(
                  children: [
                    for (var i = 0; i < widget.labels.length; i++)
                      SizedBox(
                        width: widths[i],
                        child: InkWell(
                          onTap: () => widget.controller.animateTo(i),
                          child: Center(
                            child: Text(
                              widget.labels[i],
                              maxLines: 1,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: i == widget.controller.index
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: i == widget.controller.index
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // 下划线：按 controller.animation 在"文字中心"之间插值，点击与滑动都连续跟随
                AnimatedBuilder(
                  animation: widget.controller.animation ??
                      const AlwaysStoppedAnimation<double>(0),
                  builder: (context, _) {
                    final value =
                        (widget.controller.animation?.value ?? 0).clamp(
                      0.0,
                      (widths.length - 1).toDouble(),
                    );
                    final index = value.floor();
                    final next = (index + 1).clamp(0, widths.length - 1);
                    final progress = value - index;

                    double startOf(int i) =>
                        widths.take(i).fold<double>(0, (sum, w) => sum + w);
                    final centerA = startOf(index) + widths[index] / 2;
                    final centerB = startOf(next) + widths[next] / 2;
                    final center =
                        centerA + (centerB - centerA) * progress;
                    final width = underlineWidths[index] +
                        (underlineWidths[next] - underlineWidths[index]) *
                            progress;

                    return Positioned(
                      left: center - width / 2,
                      bottom: 0,
                      width: width.clamp(12, double.infinity),
                      child: Container(
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );

          return Padding(
            padding: EdgeInsets.only(left: widget.leftPadding),
            child: needsScroll
                ? SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    child: strip,
                  )
                : strip,
          );
        },
      ),
    );
  }
}

extension on MobSlidingTabs {
  TextStyle? _labelStyle() =>
      const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.2);
}
