import 'dart:convert';

import 'package:app_containers/app_containers.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:fixnum/fixnum.dart';

/// 容器仓储的内核实现（适配器）。
///
/// 使用的都是上游公开路径：
/// - 列举：`WorkspaceService.getPrivateViews()`（首页列表的数据来源一致）
/// - 新建：`WorkspaceService.createView(name, viewSection: Private, extra: ...)`
///   —— 与侧边栏「新建页面」完全相同，保证新建的容器页能出现在页面树里；
/// - 标记：把容器信息写进 `view.extra`（上游本来就用 extra 存 font/cover 等应用级元数据）。
class ContainerRepositoryImpl implements ContainerRepository {
  ContainerRepositoryImpl({
    required this.workspaceId,
    required this.userId,
  });

  final String workspaceId;
  final Int64 userId;

  WorkspaceService get _service =>
      WorkspaceService(workspaceId: workspaceId, userId: userId);

  @override
  Future<List<ModuleContainer>> listContainers() async {
    final result = await _service.getPublicViews();
    final views = result.toNullable() ?? const <ViewPB>[];
    final containers = <ModuleContainer>[];
    for (final view in views) {
      final container = _fromView(view);
      if (container != null) {
        containers.add(container);
      }
    }
    containers.sort(
      (a, b) => _defaultOrder(a.module).compareTo(_defaultOrder(b.module)),
    );
    return containers;
  }

  @override
  Future<ModuleContainer> ensureContainer(ContainerSpec spec) async {
    final existing = (await listContainers()).firstWhere(
      (container) => container.module == spec.module,
      orElse: () => const ModuleContainer(
        viewId: '',
        name: '',
        module: '',
      ),
    );
    if (existing.viewId.isNotEmpty) {
      return existing;
    }
    return _create(name: spec.name, module: spec.module, icon: spec.icon);
  }

  /// 确保所有预设容器存在（幂等，可在启动或进入模块时调用）。
  Future<List<ModuleContainer>> ensureDefaultContainers() async {
    final created = <ModuleContainer>[];
    for (final spec in kDefaultContainers) {
      final container = await ensureContainer(spec);
      created.add(container);
    }
    Log.info(
      '[容器] 预设容器就绪：'
      '${created.map((c) => '${c.name}(${c.viewId})').join('、')}',
    );
    return created;
  }

  @override
  Future<ModuleContainer> createContainer({
    required String name,
    String icon = '📁',
  }) {
    return _create(name: name, module: ContainerModule.custom, icon: icon);
  }

  Future<ModuleContainer> _create({
    required String name,
    required String module,
    required String icon,
  }) async {
    final extra = jsonEncode({
      ContainerExtKeys.isContainerKey: true,
      ContainerExtKeys.moduleKey: module,
      ContainerExtKeys.iconKey: icon,
      ContainerExtKeys.createdAtKey: DateTime.now().millisecondsSinceEpoch,
    });
    final result = await _service.createView(
      name: name,
      // 注意：移动端首页列表渲染的是 **Public** 分区（手机端「+」新建页面用的也是 Public），
      // 容器若建在 Private 分区不会出现在页面列表里 —— 这里必须与上游一致。
      viewSection: ViewSectionPB.Public,
      extra: extra,
    );
    return result.fold(
      (view) {
        Log.info('[容器] 新建容器：$name (${view.id})');
        return ModuleContainer(
          viewId: view.id,
          name: name,
          module: module,
          icon: icon,
        );
      },
      (error) {
        Log.error('[容器] 新建容器失败：$name, ${error.msg}');
        throw Exception('新建容器失败：${error.msg}');
      },
    );
  }

  ModuleContainer? _fromView(ViewPB view) {
    final extra = view.extra;
    if (extra.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(extra);
      if (decoded is! Map) {
        return null;
      }
      final isContainer = decoded[ContainerExtKeys.isContainerKey] == true;
      if (!isContainer) {
        return null;
      }
      return ModuleContainer(
        viewId: view.id,
        name: view.name,
        module: decoded[ContainerExtKeys.moduleKey] as String? ??
            ContainerModule.custom,
        icon: decoded[ContainerExtKeys.iconKey] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// 预设容器的展示顺序；自定义容器排在最后。
  int _defaultOrder(String module) {
    final index = kDefaultContainers.indexWhere((e) => e.module == module);
    return index == -1 ? kDefaultContainers.length : index;
  }
}
