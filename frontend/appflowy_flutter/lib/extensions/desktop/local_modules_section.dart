import 'package:appflowy/extensions/kb_links/kb_links_settings_page.dart';
import 'package:appflowy/extensions/local_home/local_home_shell.dart';
import 'package:appflowy/extensions/local_home/webdav_settings_page.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
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
class LocalModulesSection extends StatelessWidget {
  const LocalModulesSection({super.key, required this.userProfile});

  final UserProfilePB userProfile;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            '本地模块',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
        _entry(
          context,
          icon: Icons.calendar_month_outlined,
          label: '日历 · 日记',
          onTap: () => open(
            CalendarView(
              workspaceId: workspaceId,
              userId: userProfile.id,
            ),
          ),
        ),
        _entry(
          context,
          icon: Icons.people_outline,
          label: 'CRM 客户',
          onTap: () => open(const CrmView()),
        ),
        _entry(
          context,
          icon: Icons.auto_awesome_outlined,
          label: 'AI 记忆',
          onTap: () => open(const AiMemoryView()),
        ),
        _entry(
          context,
          icon: Icons.hub_outlined,
          label: '知识库双链',
          onTap: () => open(const KbLinksSettingsPage()),
        ),
        _entry(
          context,
          icon: Icons.cloud_sync_outlined,
          label: '快照同步',
          onTap: () => open(WebDavSettingsPage(workspaceId: workspaceId)),
        ),
        const VSpace(6),
      ],
    );
  }

  Widget _entry(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return FlowyButton(
      onTap: onTap,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      leftIcon: Icon(icon, size: 16),
      text: FlowyText.regular(label, fontSize: 13),
      mainAxisAlignment: MainAxisAlignment.start,
      expandText: false,
    );
  }
}
