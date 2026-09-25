import 'dart:async';

import 'package:appflowy/extensions/adapters/container_repository_impl.dart';
import 'package:appflowy/extensions/local_home/local_home_shell.dart';
import 'package:appflowy/extensions/local_home/records_feed_page.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_setting.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// **侧边栏的"收起态"本体**：上游收起时整条侧栏完全滑走（宽度归零），
/// 这里改成**只留下一个图标宽度的窄条**，方便随手点开本地模块。
///
/// 关键区别（2026-09-26 产品纠正）：它**不是**在外侧另加一列，
/// 而是占据上游侧栏原来的位置（left: 0），只是宽度从 `menuWidth` 缩到 [railWidth]；
/// 点最上面的 `»` 就展开回完整侧栏（页面树 + 本地模块 + 多标签等桌面能力照旧）。
class LocalNavRail extends StatelessWidget {
  const LocalNavRail({
    super.key,
    required this.userId,
    required this.onToggleMenu,
  });

  final Int64 userId;

  /// 请求上游侧栏展开（收起态里点 `»`）。
  final VoidCallback onToggleMenu;

  /// 收起态宽度＝"一个图标的宽度"（24 图标 + 12×2 内边距）。
  static const double railWidth = 48;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 注意：workspaceId 必须在这里读 —— `UserWorkspaceBloc` 的 provider 位于桌面首页
    // 内容区内部，比"构造本地导航栏"的位置更深一层，外面读会直接抛 ProviderNotFound。
    final workspaceId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId ??
            '';
    final items = localNavItems(
      workspaceId: workspaceId,
      userId: userId,
    );
    return Container(
      width: railWidth,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          // 顶部与展开态的侧栏一致：**App 的 logo**（不再自造展开按钮，
          // 展开已有上游那个 `»`）。
          const SizedBox(height: 10),
          SizedBox(
            height: 28,
            child: Center(
              child:
                  FlowySvg(FlowySvgs.app_logo_xl, size: const Size.square(24)),
            ),
          ),
          const SizedBox(height: 6),
          Divider(
            height: 9,
            thickness: 0.5,
            indent: 12,
            endIndent: 12,
            color: theme.colorScheme.outlineVariant,
          ),
          for (final item in items)
            _RailIcon(
              icon: item.icon,
              tooltip: item.label,
              onTap: () => item.open(context),
            ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _RailIcon extends StatelessWidget {
  const _RailIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final FlowySvgData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: FlowySvg(icon, size: const Size.square(20)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一条本地导航项：图标 + 名称 + 打开动作。
///
/// 图标与移动端底栏五个标签**同一套**（参照 moodiaryCRM 的目的地图标），
/// 这样收起 / 展开 / 手机三处的入口一一对应（2026-09-26 产品纠正）。
class LocalNavItem {
  const LocalNavItem({
    required this.icon,
    required this.label,
    required this.open,
  });

  final FlowySvgData icon;
  final String label;
  final void Function(BuildContext context) open;
}

/// 桌面端与移动端**一一对应**的本地导航项（移动端底栏五标签 + 两个设置类入口）。
List<LocalNavItem> localNavItems({
  required String workspaceId,
  required Int64 userId,
}) {
  void push(BuildContext context, Widget page) {
    // PC 端**沿用上游框架**：模块页不作为全屏路由 push（那样会盖住侧栏、也没有返回路径），
    // 而是像上游"设置"那样开一个**应用内对话框**——侧栏与多标签区仍在，
    // 右上角 ✕ / Esc 就是返回（见用户 2026-09-26 反馈）。
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 900),
          child: Stack(
            children: [
              Navigator(
                onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => page),
              ),
              // 明确的返回入口（点遮罩或 Esc 也能关，但给个看得见的 ✕ 更稳）
              Positioned(
                right: 4,
                top: 4,
                child: IconButton(
                  tooltip: '关闭（返回工作区）',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  return [
    LocalNavItem(
      icon: FlowySvgs.document_s,
      label: '记录流（首页）',
      open: (context) => push(
        context,
        RecordsFeedPage(
          repository: ContainerRepositoryImpl(
            workspaceId: workspaceId,
            userId: userId,
          ),
        ),
      ),
    ),
    LocalNavItem(
      icon: FlowySvgs.calendar_s,
      label: '日历 · 日记',
      open: (context) => push(
        context,
        CalendarView(workspaceId: workspaceId, userId: userId),
      ),
    ),
    LocalNavItem(
      icon: FlowySvgs.person_s,
      label: 'CRM',
      open: (context) => push(context, const CrmView()),
    ),
    LocalNavItem(
      icon: FlowySvgs.ai_sparks_s,
      label: 'AI 记忆',
      open: (context) => push(context, const AiMemoryView()),
    ),
    LocalNavItem(
      // 与展开态侧栏「本地模块」里的图标同源，不另起一套
      icon: FlowySvgs.settings_sync_m,
      label: '设置',
      open: (context) => showSettingsDialog(
        context,
        userWorkspaceBloc: context.read<UserWorkspaceBloc>(),
      ),
    ),
  ];
}

/// 抽屉态：左侧滑出的浮层导航（图标 + 文字）。
Future<void> showLocalNavDrawer(
  BuildContext context, {
  required String workspaceId,
  required Int64 userId,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '本地导航',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (dialogContext, animation, _, __) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return Align(
        alignment: Alignment.centerLeft,
        child: FractionalTranslation(
          translation: Offset(-1 + curved.value, 0),
          child: LocalNavDrawer(
            workspaceId: workspaceId,
            userId: userId,
          ),
        ),
      );
    },
  );
}

/// 抽屉内容（也给悬停/窄屏复用）。
class LocalNavDrawer extends StatelessWidget {
  const LocalNavDrawer({
    super.key,
    required this.workspaceId,
    required this.userId,
  });

  final String workspaceId;
  final Int64 userId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = localNavItems(workspaceId: workspaceId, userId: userId);
    return Material(
      color: theme.colorScheme.surface,
      child: SizedBox(
        width: 240,
        height: double.infinity,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(
                  '本地模块',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final item in items)
                ListTile(
                  dense: true,
                  leading: FlowySvg(item.icon, size: const Size.square(20)),
                  title: Text(item.label),
                  onTap: () {
                    Navigator.of(context).pop();
                    item.open(context);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
