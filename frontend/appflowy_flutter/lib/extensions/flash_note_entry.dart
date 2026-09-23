import 'package:app_biz_store/app_biz_store.dart';
import 'package:app_flash_note/app_flash_note.dart';
import 'package:appflowy/extensions/adapters/flash_note_document_gateway_impl.dart';
import 'package:appflowy/mobile/application/mobile_router.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:universal_platform/universal_platform.dart';

/// 打开闪念收件箱（App 侧入口装配）。
///
/// 装配内容：
/// - 业务库：`<应用数据目录>/business/business.db`（独立 sqlite，与内核库分离）
/// - 文档网关：内核 `ViewBackendService`（落成知识库页面）
Future<void> openFlashNoteInbox(
  BuildContext context, {
  required String workspaceId,
  required Int64 userId,
}) async {
  final baseDirectory = await getIt<ApplicationDataStorage>().getPath();
  final database = await BusinessDatabase.open(
    directory: baseDirectory,
    migrations: kFlashNoteMigrations,
  );
  final service = FlashNoteService(
    repository: FlashNoteRepository(database),
    documentGateway: CoreFlashNoteDocumentGateway(
      workspaceId: workspaceId,
      userId: userId,
    ),
  );

  if (!context.mounted) {
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FlashNoteInboxPage(
        service: service,
        onOpenDocument: (documentId) => openDocumentByViewId(
          context,
          documentId,
        ),
      ),
    ),
  );
}

/// 按 view id 打开内核页面（移动端 pushView，桌面端开 tab）。
Future<void> openDocumentByViewId(
  BuildContext context,
  String viewId,
) async {
  final result = await ViewBackendService.getView(viewId);
  final view = result.toNullable();
  if (view == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('页面不存在或已被删除')));
    }
    return;
  }
  if (!context.mounted) {
    return;
  }
  if (UniversalPlatform.isMobile) {
    await context.pushView(view);
  } else {
    getIt<TabsBloc>().add(TabsEvent.openPlugin(plugin: view.plugin()));
  }
}
