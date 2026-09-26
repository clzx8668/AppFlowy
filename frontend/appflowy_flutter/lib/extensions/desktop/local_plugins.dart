import 'package:appflowy/extensions/adapters/container_repository_impl.dart';
import 'package:appflowy/extensions/local_home/records_feed_page.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pbenum.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// **本地模块插件**：把自研模块页注册成上游插件，从而"像打开文档一样"在内容区
/// 开出一个真正的标签（标签条、窗口标题行、分享/收藏等上游元素全部保留）——
/// 这是用户 2026-09-26 明确的验收标准（详见 doc/全局完善计划（多轮）.md 第四节）。
///
/// 写法照搬上游 `lib/plugins/blank/blank.dart` 的三件套：
/// `PluginBuilder`（注册用）+ `Plugin`（实例）+ `PluginWidgetBuilder`（内容）。
/// `layoutType` 用 `ViewLayoutPB.Document`（不新建视图，纯前端标签）。
class LocalRecordsPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) => LocalRecordsPlugin();

  @override
  String get menuName => '记录流（首页）';

  @override
  FlowySvgData get icon => FlowySvgs.document_s;

  @override
  PluginType get pluginType => PluginType.localRecords;

  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Document;
}

/// 本地模块插件都不应该出现在"新建"菜单里（入口在侧栏/窄条上）。
class LocalModulePluginConfig implements PluginConfig {
  @override
  bool get creatable => false;
}

class LocalRecordsPlugin extends Plugin {
  @override
  PluginWidgetBuilder get widgetBuilder => LocalRecordsWidgetBuilder();

  @override
  PluginId get id => 'local_records';

  @override
  PluginType get pluginType => PluginType.localRecords;
}

class LocalRecordsWidgetBuilder extends PluginWidgetBuilder
    with NavigationItem {
  @override
  String? get viewName => '记录流';

  @override
  Widget get leftBarItem => FlowyText.medium('记录流');

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) => leftBarItem;

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) {
    // 用 Builder 拿到内容区所在的 context，才能读到 UserWorkspaceBloc
    // （插件构造时没有 BuildContext）。
    return Builder(
      builder: (context) {
        final workspaceBloc = context.read<UserWorkspaceBloc>().state;
        return RecordsFeedPage(
          repository: ContainerRepositoryImpl(
            workspaceId: workspaceBloc.currentWorkspace?.workspaceId ?? '',
            userId: workspaceBloc.userProfile.id,
          ),
        );
      },
    );
  }

  @override
  List<NavigationItem> get navigationItems => [this];
}
