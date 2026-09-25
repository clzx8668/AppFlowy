import 'dart:async';

import 'package:appflowy/extensions/adapters/container_repository_impl.dart';
import 'package:appflowy/extensions/kb_links/kb_links_settings_page.dart';
import 'package:appflowy/extensions/local_home/local_home_shell.dart';
import 'package:appflowy/extensions/local_home/records_feed_page.dart';
import 'package:appflowy/extensions/local_home/webdav_settings_page.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// 桌面端「本地导航栏」—— 三态侧栏，与移动端同构。
///
/// - **压缩态（默认最窄）**：宽 [railWidth]，只留单列图标 + 悬浮提示。
///   上游侧栏收起时以前是"什么都没有"，现在始终留一条导航栏；
/// - **展开态**：一键展开上游完整侧栏（页面树 + 本地模块），保留桌面多标签/拖拽/大纲能力；
/// - **抽屉态**：浮层抽屉（图标 + 文字），任何窗口宽度都能用，点遮罩关闭。
///
/// 为什么单独一条栏而不是改上游侧栏内部：上游 `HomeSideBar` 结构复杂（空间、收藏、页面树、
/// 回收站…），我们只做**加法**——把自己的一列图标放在最左边，其余一律不碰，
/// 这样上游升级不会冲突（见《代码开发规范与工程规约》"只新增不删除"）。
class LocalNavRail extends StatelessWidget {
  const LocalNavRail({
    super.key,
    required this.userId,
    required this.menuExpanded,
    required this.onToggleMenu,
  });

  final Int64 userId;

  /// 上游侧栏当前是否展开（来自 `HomeSettingBloc.menuStatus`）。
  final bool menuExpanded;

  /// 请求上游侧栏展开 / 收起。
  final VoidCallback onToggleMenu;

  /// 压缩态宽度（最窄单列：40 图标 + 8×2 内边距）。
  static const double railWidth = 56;

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
          const SizedBox(height: 8),
          _RailIcon(
            icon: Icons.workspaces_outline,
            tooltip: menuExpanded ? '收起侧边栏' : '展开侧边栏',
            selected: menuExpanded,
            onTap: onToggleMenu,
          ),
          const SizedBox(height: 4),
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
          _RailIcon(
            icon: Icons.menu_open,
            tooltip: '抽屉模式（图标 + 文字）',
            onTap: () => unawaited(
              showLocalNavDrawer(
                context,
                workspaceId: workspaceId,
                userId: userId,
              ),
            ),
          ),
          const SizedBox(height: 8),
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
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: selected ? scheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                icon,
                size: 20,
                color: selected
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一条本地导航项：图标 + 名称 + 打开动作。
class LocalNavItem {
  const LocalNavItem({
    required this.icon,
    required this.label,
    required this.open,
  });

  final IconData icon;
  final String label;
  final void Function(BuildContext context) open;
}

/// 桌面端与移动端**一一对应**的本地导航项（移动端底栏五标签 + 两个设置类入口）。
List<LocalNavItem> localNavItems({
  required String workspaceId,
  required Int64 userId,
}) {
  void push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  return [
    LocalNavItem(
      icon: Icons.article_outlined,
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
      icon: Icons.calendar_month_outlined,
      label: '日历 · 日记',
      open: (context) => push(
        context,
        CalendarView(workspaceId: workspaceId, userId: userId),
      ),
    ),
    LocalNavItem(
      icon: Icons.groups_outlined,
      label: 'CRM',
      open: (context) => push(context, const CrmView()),
    ),
    LocalNavItem(
      icon: Icons.auto_awesome_outlined,
      label: 'AI 记忆',
      open: (context) => push(context, const AiMemoryView()),
    ),
    LocalNavItem(
      icon: Icons.hub_outlined,
      label: '知识库双链',
      open: (context) => push(context, const KbLinksSettingsPage()),
    ),
    LocalNavItem(
      icon: Icons.cloud_sync_outlined,
      label: '快照同步',
      open: (context) =>
          push(context, WebDavSettingsPage(workspaceId: workspaceId)),
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
                  leading: Icon(item.icon, size: 20),
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
