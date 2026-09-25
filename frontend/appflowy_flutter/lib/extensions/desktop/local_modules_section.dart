import 'dart:async';

import 'package:app_containers/app_containers.dart';
import 'package:appflowy/extensions/adapters/container_repository_impl.dart';
import 'package:appflowy/extensions/kb_links/kb_links_settings_page.dart';
import 'package:appflowy/extensions/local_home/local_home_shell.dart';
import 'package:appflowy/extensions/local_home/webdav_settings_page.dart';
import 'package:appflowy/extensions/timeline_entry.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart'
    show UserProfilePB;
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// 桌面端（Windows）的"本地模块"入口区。
///
/// 为什么需要它：我们的日历/CRM/AI 记忆/同步设置是**移动端外壳里的页面**，
/// 桌面端走的是上游侧边栏布局，不接这段入口的话，桌面用户根本进不去这些模块
/// （见《二次开发改动记录》步骤⑰的缺口说明）。
///
/// 实现取向：复用移动端已经验证过的页面组件（[CalendarView] / [CrmView] /
/// [AiMemoryView]），桌面端只做"入口 + 路由"，不复制业务逻辑；
/// 上游改动量 = 在 `sidebar.dart` 里插入一行本组件。
///
/// 样式对齐（2026-09-25 用户反馈"与原有元素不统一"后修正）：
/// - 整段必须 `width: double.infinity` —— 侧栏外层 Column 的 crossAxisAlignment 是 center，
///   不撑满宽度的话整块会被居中，看起来像缩进了一大截；
/// - 每一行复用「新页面」按钮的写法（FlowyButton + 20px FlowySvg + FlowyText.regular +
///   `margin: EdgeInsets.only(left: 4)` / `iconPadding: 8`），文案字号与行高也和它一致；
/// - 小节标题用上游 `FlowyText(fontSize: 12, color: hintColor)` 的写法（与"收藏夹""个人的"同级）。
class LocalModulesSection extends StatefulWidget {
  const LocalModulesSection({super.key, required this.userProfile});

  final UserProfilePB userProfile;

  @override
  State<LocalModulesSection> createState() => _LocalModulesSectionState();
}

class _LocalModulesSectionState extends State<LocalModulesSection> {
  /// 只在会话内跑一次：桌面端也执行结构对齐 + 时间线初始化。
  ///
  /// 为什么放在这里：结构对齐原本只挂在移动端外壳（`LocalHomeShell`）上，
  /// 全新安装的桌面端不会创建「笔记/日历/CRM/AI 交流」这四个分类容器与「时间线」数据库。
  /// 侧栏是桌面端一定会渲染的组件，借它触发一次即可（幂等，失败只记日志）。
  static bool _initialized = false;

  @override
  void initState() {
    super.initState();
    if (!_initialized) {
      _initialized = true;
      unawaited(_bootstrapStructure());
    }
  }

  Future<void> _bootstrapStructure() async {
    try {
      final workspaceId = context
              .read<UserWorkspaceBloc>()
              .state
              .currentWorkspace
              ?.workspaceId ??
          '';
      if (workspaceId.isEmpty) {
        _initialized = false; // 工作区还没就绪，下次重建时再试
        return;
      }
      final repository = ContainerRepositoryImpl(
        workspaceId: workspaceId,
        userId: widget.userProfile.id,
      );
      await repository.alignStructure();
      final containers = await repository.listContainers();
      for (final container in containers) {
        if (container.module == ContainerModule.diary) {
          await ensureTimelinePage(parentViewId: container.viewId);
          break;
        }
      }
    } catch (e) {
      _initialized = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workspaceId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId ??
            '';

    void open(Widget page) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => page),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
            child: FlowyText(
              '本地模块',
              fontSize: 12.0,
              color: theme.hintColor,
            ),
          ),
          _entry(
            context,
            icon: FlowySvgs.calendar_s,
            label: '日历 · 日记',
            onTap: () => open(
              CalendarView(
                workspaceId: workspaceId,
                userId: widget.userProfile.id,
              ),
            ),
          ),
          _entry(
            context,
            icon: FlowySvgs.person_s,
            label: 'CRM 客户',
            onTap: () => open(const CrmView()),
          ),
          _entry(
            context,
            icon: FlowySvgs.ai_sparks_s,
            label: 'AI 记忆',
            onTap: () => open(const AiMemoryView()),
          ),
          _entry(
            context,
            icon: FlowySvgs.link_to_page_s,
            label: '知识库双链',
            onTap: () => open(const KbLinksSettingsPage()),
          ),
          _entry(
            context,
            icon: FlowySvgs.settings_sync_m,
            label: '快照同步',
            onTap: () => open(WebDavSettingsPage(workspaceId: workspaceId)),
          ),
          const VSpace(6),
        ],
      ),
    );
  }

  Widget _entry(
    BuildContext context, {
    required FlowySvgData icon,
    required String label,
    required VoidCallback onTap,
    double leftIconSize = 20,
  }) {
    // 与上游「新页面」按钮保持同一行样式：同高、同左内边距、同图标间距
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: HomeSizes.newPageSectionHeight,
      child: FlowyButton(
        onTap: onTap,
        leftIcon: FlowySvg(
          icon,
          blendMode: null,
        ),
        leftIconSize: Size.square(leftIconSize),
        margin: const EdgeInsets.only(left: 4.0),
        iconPadding: 8.0,
        text: FlowyText.regular(label, lineHeight: 1.15),
      ),
    );
  }
}
