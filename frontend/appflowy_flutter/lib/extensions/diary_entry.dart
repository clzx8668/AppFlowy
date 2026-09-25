import 'dart:async';

import 'package:app_biz_store/app_biz_store.dart';
import 'package:app_containers/app_containers.dart';
import 'package:app_diary_time/app_diary_time.dart';
import 'package:appflowy/extensions/adapters/container_repository_impl.dart';
import 'package:appflowy/extensions/timeline_entry.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:fixnum/fixnum.dart';

/// 装配日记服务：业务库（日记表）+ 内核文档网关（日记正文落在「笔记」容器下）。
Future<DiaryService> createDiaryService({
  required String workspaceId,
  required Int64 userId,
}) async {
  final baseDirectory = await getIt<ApplicationDataStorage>().getPath();
  final database = await BusinessDatabase.open(
    directory: baseDirectory,
    migrations: kDiaryMigrations,
  );

  // 日记文档默认落「笔记 → 生活日记」这个普通子页面下
  // （产品确认的新结构：容器只做分类，具体归档用普通子页面，沿用上游页面树）
  final containers = await ContainerRepositoryImpl(
    workspaceId: workspaceId,
    userId: userId,
  ).ensureDefaultContainers();
  final noteContainer = containers.firstWhere(
    (container) => container.module == kDiaryParentContainerModule,
    orElse: () => containers.first,
  );

  return DiaryService(
    repository: DiaryRepositoryImpl(database),
    documentGateway: _CoreDiaryDocumentGateway(
      containerId: noteContainer.viewId,
      parentPageName: kDiaryParentPageName,
    ),
  );
}

/// 日记文档网关的内核实现：同名标题（日期）已存在则复用，否则新建。
class _CoreDiaryDocumentGateway implements DiaryDocumentGateway {
  const _CoreDiaryDocumentGateway({
    required this.containerId,
    required this.parentPageName,
  });

  /// 日记所属的分类容器（「笔记」）。
  final String containerId;

  /// 归档日记的子页面名（「生活日记」）。
  final String parentPageName;

  /// 「生活日记」子页面 id 的进程内缓存（避免每天都去列一次子页面）。
  static String? _parentCache;

  @override
  Future<String> ensureDailyDocument({
    required DateTime date,
    required String title,
  }) async {
    final parentViewId = await _ensureParentPage();

    // 先在同一父页面下找同名（标题=日期）的页面
    final all = await ViewBackendService.getAllViews();
    final views = all.toNullable()?.items ?? const <ViewPB>[];
    for (final view in views) {
      if (view.parentViewId == parentViewId && view.name == title) {
        return view.id;
      }
    }

    // 没有则新建（与闪念落库同一条内核路径：指定父页面创建 Document）
    final created = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parentViewId,
      name: title,
    );
    return created.fold(
      (view) {
        // 二次开发：日记同时登记到「时间线」数据库（统一时间轴）
        unawaited(
          recordTimelineEvent(
            date: date,
            kind: TimelineKind.diary,
            title: title,
            sourceViewId: view.id,
          ),
        );
        return view.id;
      },
      (error) {
        Log.error('[日记] 创建日记文档失败：$title, ${error.msg}');
        throw Exception('创建日记文档失败：${error.msg}');
      },
    );
  }

  /// 确保「生活日记」子页面存在并返回其 id（幂等）。
  Future<String> _ensureParentPage() async {
    final cached = _parentCache;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final children = await ViewBackendService.getChildViews(viewId: containerId);
    for (final view in children.toNullable() ?? const <ViewPB>[]) {
      if (view.name == parentPageName) {
        return _parentCache = view.id;
      }
    }
    final created = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: containerId,
      name: parentPageName,
    );
    return created.fold(
      (view) => _parentCache = view.id,
      (error) {
        Log.error('[日记] 创建「$parentPageName」失败：${error.msg}');
        throw Exception('创建「$parentPageName」失败：${error.msg}');
      },
    );
  }
}
