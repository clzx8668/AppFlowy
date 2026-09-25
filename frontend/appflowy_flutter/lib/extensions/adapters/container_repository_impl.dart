import 'dart:convert';

import 'package:app_containers/app_containers.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
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
/// - 移动/改名：`ViewBackendService.moveViewV2` / `updateView`（结构对齐迁移用）；
/// - 标记：把容器信息写进 `view.extra`（上游本来就用 extra 存 font/cover 等应用级元数据）。
///
/// 结构约定（2026-09-25 与产品确认）：容器就是**普通顶层页面**（和默认的 Getting started
/// 页面同类），只是多写一组 `af_*` 标记；「闪念 / 工作记录 / 生活日记」是「笔记」容器下的
/// **普通子页面**，可继续无限嵌套 —— 全程不引入任何新的数据模型。
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

  /// 结构对齐（幂等，启动时调用一次即可）：
  ///
  /// 1. 历史迁移：早期「闪念」是一个**顶层容器**，现在按新结构降级为「笔记」下的子页面 ——
  ///    用内核 `moveViewV2` 改父节点 + `updateView` 去掉容器标记，**页面与正文完全不动**；
  /// 2. 在「笔记」容器下补齐默认子页面（闪念 / 工作记录 / 生活日记）——
  ///    它们就是普通页面，沿用上游"无限嵌套"的模型；
  /// 3. 把散落在「笔记」容器根部的日记页（标题 `yyyy-MM-dd`）收进「生活日记」子页面。
  ///
  /// 全程只动页面树结构，不删除任何内容；任何一步失败都只记日志，不影响启动。
  Future<void> alignStructure() async {
    try {
      final containers = await ensureDefaultContainers();
      final noteContainer = containers.firstWhere(
        (c) => c.module == ContainerModule.note,
      );

      // 1) 旧「闪念」容器先降级，再补子页面（先后顺序很重要：否则会出现两个「闪念」）
      final legacyFlashNote = (await listContainers()).firstWhere(
        (c) => c.module == ContainerModule.flashNote,
        orElse: () => const ModuleContainer(
          viewId: '',
          name: '',
          module: '',
        ),
      );
      if (legacyFlashNote.viewId.isNotEmpty) {
        await ViewBackendService.moveViewV2(
          viewId: legacyFlashNote.viewId,
          newParentId: noteContainer.viewId,
          prevViewId: null,
          fromSection: ViewSectionPB.Public,
          toSection: ViewSectionPB.Public,
        );
        // 去掉容器标记（只留图标字段，页面树里仍有 emoji）；
        // 页面本身、它的子页面与全部正文都不动。
        await ViewBackendService.updateView(
          viewId: legacyFlashNote.viewId,
          extra: jsonEncode({
            ContainerExtKeys.iconKey: legacyFlashNote.icon ?? '⚡️',
          }),
        );
        Log.info('[容器] 旧「闪念」容器已降级为「笔记」下的子页面');
      }

      // 2) 笔记容器下的默认子页面
      final subPageIds = <String, String>{};
      for (final sub in kDefaultSubPages[ContainerModule.note] ?? const []) {
        final pageId = await _ensureChildPage(
          parentId: noteContainer.viewId,
          name: sub.name,
        );
        subPageIds[sub.name] = pageId;
      }

      // 3) 把散落在「笔记」根部的日记页收进「生活日记」
      final diaryParentId = subPageIds[kDiaryParentPageName];
      if (diaryParentId != null) {
        final children = await ViewBackendService.getChildViews(
          viewId: noteContainer.viewId,
        );
        for (final view in children.toNullable() ?? const <ViewPB>[]) {
          if (!_isDiaryTitle(view.name)) {
            continue;
          }
          await ViewBackendService.moveViewV2(
            viewId: view.id,
            newParentId: diaryParentId,
            prevViewId: null,
            fromSection: ViewSectionPB.Public,
            toSection: ViewSectionPB.Public,
          );
          Log.info('[容器] 日记页 ${view.name} 已收进「生活日记」');
        }
      }

      Log.info(
        '[容器] 结构对齐完成：笔记=${noteContainer.viewId} '
        '子页面=${subPageIds.entries.map((e) => '${e.key}:${e.value}').join('、')}',
      );
    } catch (e) {
      Log.error('[容器] 结构对齐失败（忽略，不影响使用）：$e');
    }
  }

  /// 找到（没有就创建）某容器下指定名字的普通子页面，返回其 view id。
  Future<String> _ensureChildPage({
    required String parentId,
    required String name,
  }) async {
    final children = await ViewBackendService.getChildViews(viewId: parentId);
    for (final view in children.toNullable() ?? const <ViewPB>[]) {
      if (view.name == name) {
        return view.id;
      }
    }
    final created = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parentId,
      name: name,
    );
    return created.fold(
      (view) => view.id,
      (error) {
        Log.error('[容器] 创建子页面失败：$name, ${error.msg}');
        throw Exception('创建子页面失败：${error.msg}');
      },
    );
  }

  /// 标题形如 `2026-09-25` 的页面视为日记页。
  bool _isDiaryTitle(String name) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(name.trim());

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
