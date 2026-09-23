import 'package:app_biz_store/app_biz_store.dart';
import 'package:app_containers/app_containers.dart';
import 'package:app_diary_time/app_diary_time.dart';
import 'package:appflowy/extensions/adapters/container_repository_impl.dart';
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

  // 日记文档默认落「笔记」容器（与产品确认一致；要独立成容器只需改这里）
  final containers = await ContainerRepositoryImpl(
    workspaceId: workspaceId,
    userId: userId,
  ).ensureDefaultContainers();
  final noteContainer = containers.firstWhere(
    (container) => container.module == ContainerModule.note,
    orElse: () => containers.first,
  );

  return DiaryService(
    repository: DiaryRepositoryImpl(database),
    documentGateway: _CoreDiaryDocumentGateway(
      parentViewId: noteContainer.viewId,
    ),
  );
}

/// 日记文档网关的内核实现：同名标题（日期）已存在则复用，否则新建。
class _CoreDiaryDocumentGateway implements DiaryDocumentGateway {
  const _CoreDiaryDocumentGateway({required this.parentViewId});

  final String parentViewId;

  @override
  Future<String> ensureDailyDocument({
    required DateTime date,
    required String title,
  }) async {
    // 先在同一容器下找同名（标题=日期）的页面
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
      (view) => view.id,
      (error) {
        Log.error('[日记] 创建日记文档失败：$title, ${error.msg}');
        throw Exception('创建日记文档失败：${error.msg}');
      },
    );
  }
}
