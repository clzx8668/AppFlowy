import 'dart:async';

import 'package:appflowy/extensions/adapters/container_repository_impl.dart';
import 'package:appflowy/extensions/kb_links/kb_links_settings_page.dart';
import 'package:appflowy/extensions/local_home/local_home_shell.dart';
import 'package:appflowy/extensions/local_home/webdav_settings_page.dart';
import 'package:appflowy/extensions/local_home/records_feed_page.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_setting.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy/workspace/presentation/command_palette/command_palette.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// **内容区（侧栏右边那块）的内嵌 Navigator key**。
///
/// 桌面端要求在"主框架内渲染内部页"（侧栏、多标签区都不动）：
/// `DesktopHomeScreen` 把内容区包一层 Navigator，模块页 push 到它上面，
/// 返回栈只影响内容区 —— 与上游打开文档的行为一致（用户 2026-09-26 要求）。
final GlobalKey<NavigatorState> localContentViewKey =
    GlobalKey<NavigatorState>();

/// 在内容区打开一个本地模块页（拿不到 Navigator 时退化为普通路由）。
void openLocalModulePage(BuildContext context, Widget page) {
  // 桌面端**在内容区（主框架内）渲染**：push 到内容区自带的那层 Navigator，
  // 侧栏与多标签区不动，返回栈只影响内容区。
  final navigator = localContentViewKey.currentState;
  if (navigator != null) {
    navigator.push(MaterialPageRoute(builder: (_) => page));
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

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
          // A 方案：窄条要能装下"展开态侧栏的全部一级项"（含用户自建页面），
          // 因此图标区可上下滚动，顶部 logo 固定不动。
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // 固定项（与展开态侧栏顶部一一对应）：我 / 设置 / 通知
                  _RailHeaderItems(),
                  // 与展开态侧栏「新页面」一行对应
                  const _RailNewPageIcon(),
                  // 与展开态侧栏「搜索」一行对应（同一入口：命令面板）
                  const _RailSearchIcon(),
                  for (final item in items)
                    _RailIcon(
                      icon: item.icon,
                      tooltip: item.label,
                      onTap: () => item.open(context),
                    ),
                  // A 方案第 2 部分：**动态一级页面**（"个人的"下的顶层视图），
                  // 与展开态侧栏读同一个数据源，点击用上游原有方式打开（打开为内容区页面）。
                  _RailPageIcons(),
                ],
              ),
            ),
          ),
          // 固定项（与展开态侧栏底部对应）：回收站
          Divider(
            height: 9,
            thickness: 0.5,
            indent: 12,
            endIndent: 12,
            color: theme.colorScheme.outlineVariant,
          ),
          _RailChildIcon(
            tooltip: '回收站',
            onTap: () {
              getIt<MenuSharedState>().latestOpenView = null;
              getIt<TabsBloc>().add(
                TabsEvent.openPlugin(
                  plugin: makePlugin(pluginType: PluginType.trash),
                ),
              );
            },
            child: const Icon(Icons.delete_outline, size: 20),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 窄条里的**动态一级页面图标**：读的是与展开态侧栏同一个数据源
/// （`getIt<WorkspaceService>().getPrivateViews()`），点一个就按上游原有方式打开该页面。
///
/// 说明：第一版所有页面共用文档图标 + 中文名 tooltip；
/// "每个页面显示自己的图标（emoji/自定义）"紧接着补。
class _RailPageIcons extends StatelessWidget {
  const _RailPageIcons();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ViewPB>>(
      future: getIt<WorkspaceService>().getPrivateViews().then(
            (result) => result.getOrThrow(),
          ),
      builder: (context, snapshot) {
        final views = snapshot.data;
        if (views == null || views.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          children: [
            const SizedBox(height: 4),
            Divider(
              height: 9,
              thickness: 0.5,
              indent: 12,
              endIndent: 12,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            for (final view in views) _RailViewIcon(view: view),
          ],
        );
      },
    );
  }
}

/// 按**上游原有方式**打开一个页面（内容区里的标签页），与展开态侧栏点页面一致。
Future<void> openViewInContent(BuildContext context, ViewPB view) async {
  getIt<TabsBloc>().add(TabsEvent.openPlugin(plugin: view.plugin()));
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
    // 在主框架的内容区里渲染（侧栏不动；内容区自带返回）
    openLocalModulePage(context, page);
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
      icon: FlowySvgs.link_to_page_s,
      label: '知识库双链',
      open: (context) => push(context, const KbLinksSettingsPage()),
    ),
    LocalNavItem(
      icon: FlowySvgs.settings_sync_m,
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

/// 动态一级页面的图标：优先用页面自己的 emoji，没有则用该页面类型的默认图标
/// —— 与展开态侧栏 `view_item.dart` 的取法完全一致。
class _RailViewIcon extends StatelessWidget {
  const _RailViewIcon({required this.view});

  final ViewPB view;

  @override
  Widget build(BuildContext context) {
    final iconData = view.icon.toEmojiIconData();
    final child = iconData.isNotEmpty
        ? RawEmojiIconWidget(
            emoji: iconData,
            emojiSize: 16.0,
            lineHeight: 18.0 / 16.0,
          )
        : Opacity(opacity: 0.6, child: view.defaultIcon());
    return Tooltip(
      message: view.name.isEmpty ? '未命名' : view.name,
      waitDuration: const Duration(milliseconds: 300),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => unawaited(openViewInContent(context, view)),
            child: SizedBox(width: 40, height: 40, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}

/// 展开态侧栏**顶部那一行**的图标版：我（头像）/ 设置 / 通知。
class _RailHeaderItems extends StatelessWidget {
  const _RailHeaderItems();

  @override
  Widget build(BuildContext context) {
    final profile = context.read<UserWorkspaceBloc>().state.userProfile;
    final initial = profile.name.isEmpty ? 'A' : profile.name.characters.first;
    return Column(
      children: [
        _RailChildIcon(
          tooltip: profile.name.isEmpty ? '本地用户' : profile.name,
          onTap: () => showSettingsDialog(
            context,
            userWorkspaceBloc: context.read<UserWorkspaceBloc>(),
          ),
          child: CircleAvatar(radius: 13, child: Text(initial)),
        ),
        _RailChildIcon(
          tooltip: '设置',
          onTap: () => showSettingsDialog(
            context,
            userWorkspaceBloc: context.read<UserWorkspaceBloc>(),
          ),
          child: const Icon(Icons.settings_outlined, size: 20),
        ),
        _RailChildIcon(
          tooltip: '通知',
          onTap: () => context.read<HomeSettingBloc>().add(
                const HomeSettingEvent.collapseNotificationPanel(),
              ),
          child: const Icon(Icons.notifications_none, size: 20),
        ),
      ],
    );
  }
}

/// 任意子节点的窄条图标（头像、Material 图标都能用）。
class _RailChildIcon extends StatelessWidget {
  const _RailChildIcon({
    required this.child,
    required this.tooltip,
    required this.onTap,
  });

  final Widget child;
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
            child: SizedBox(width: 40, height: 40, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}

/// 「新页面」：复用上游侧栏 `SidebarNewPageButton` 里那套创建逻辑（不改行为），只换成图标。
class _RailNewPageIcon extends StatelessWidget {
  const _RailNewPageIcon();

  Future<void> _createNewPage(BuildContext context) async {
    final section = context.read<UserWorkspaceBloc>().state.isCollabWorkspaceOn
        ? ViewSectionPB.Private
        : ViewSectionPB.Public;
    final spaceState = context.read<SpaceBloc>().state;
    if (spaceState.spaces.isNotEmpty) {
      context.read<SpaceBloc>().add(
            const SpaceEvent.createPage(
              name: '',
              index: 0,
              layout: ViewLayoutPB.Document,
              openAfterCreate: true,
            ),
          );
    } else {
      context.read<SidebarSectionsBloc>().add(
            SidebarSectionsEvent.createRootViewInSection(
              name: '',
              viewSection: section,
              index: 0,
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _RailChildIcon(
      tooltip: '新页面',
      onTap: () => unawaited(_createNewPage(context)),
      child: const Icon(Icons.add, size: 20),
    );
  }
}

/// 「搜索」：与展开态侧栏那行同一个入口（命令面板）。
class _RailSearchIcon extends StatelessWidget {
  const _RailSearchIcon();

  @override
  Widget build(BuildContext context) {
    return _RailChildIcon(
      tooltip: '搜索',
      onTap: () => CommandPalette.of(context).toggle(
        workspaceBloc: context.read<UserWorkspaceBloc>(),
        spaceBloc: context.read<SpaceBloc>(),
      ),
      child: const Icon(Icons.search, size: 20),
    );
  }
}
