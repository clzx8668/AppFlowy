import 'package:app_flash_note/app_flash_note.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace/workspace_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:collection/collection.dart';
import 'package:fixnum/fixnum.dart';

/// 闪念页面统一收纳的容器页面名（首次使用自动创建）。
const String kFlashNoteContainerName = '闪念';

/// 用于定位"可见容器"的系统页面名（每个工作空间默认都有）。
const String _kAnchorPageName = 'Getting started';

/// 闪念落成文档的内核实现（适配器）。
///
/// 只做一件事：把"一段文字"变成内核里一篇带正文的 Document 页面。
/// 全程使用内核既有公开 API：
/// - `ViewBackendService.createView(initialDataBytes: ...)`：创建页面并写入初始内容；
/// - `DocumentDataPBFromTo.fromDocument(...)`：把编辑器文档模型转成内核识别的数据。
///
/// 之所以把这段放在 App 侧而不是扩展包里：`appflowy_editor` 在本仓库是 git 依赖覆盖，
/// 且转换器属于 App 内部代码，扩展包不应反向依赖 App（依赖倒置，见
/// `doc/现有模块复用与扩展分析.md` 第三节）。
class CoreFlashNoteDocumentGateway implements FlashNoteDocumentGateway {
  const CoreFlashNoteDocumentGateway({
    required this.workspaceId,
    required this.userId,
  });

  /// 当前工作空间 id。
  final String workspaceId;

  /// 当前用户 id（查询工作空间视图需要）。
  final Int64 userId;

  static const ViewSectionPB _section = ViewSectionPB.Private;

  @override
  Future<String> createDocument({
    required String title,
    required String body,
    required DateTime createdAt,
  }) async {
    final parentViewId = await _resolveContainerViewId();

    // 首选：带正文创建（内核 initial_data 走 DocumentDataPB 二进制 protobuf）。
    final withContent = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parentViewId,
      name: title,
      initialDataBytes: _buildInitialData(body),
      section: _section,
    );
    final view = withContent.toNullable();
    if (view != null) {
      return view.id;
    }

    // 兜底：正文写入失败时，至少把闪念落成一篇标题页，保证闭环不中断
    // （闪念原文始终在业务库里，不会丢）。
    Log.warn(
      '[闪念] 带正文创建页面失败，降级为仅标题页面：'
      '${withContent.getFailure().msg}',
    );
    final titleOnly = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parentViewId,
      name: title,
      section: _section,
    );
    return titleOnly.fold(
      (view) => view.id,
      (error) => throw Exception('创建页面失败：${error.msg}'),
    );
  }

  /// 解析闪念页面的容器视图：优先复用已存在的「闪念」页面，否则新建一个。
  ///
  /// 说明：本地工作空间下，只有"挂在某个真实页面下"的视图确定会出现在侧边栏
  /// （与上游"新建页面"同一路径）；因此容器页挂在用户已有页面之下，闪念页面再挂在容器页下，
  /// 这样闪念在知识库里始终可见、成组、可检索。
  Future<String> _resolveContainerViewId() async {
    final service = WorkspaceService(workspaceId: workspaceId, userId: userId);

    final privates = (await service.getPrivateViews()).toNullable() ?? const [];
    final existing = privates.firstWhereOrNull(
      (view) => view.name == kFlashNoteContainerName,
    );
    if (existing != null) {
      return existing.id;
    }

    // 用系统页面做锚点，取其父视图（即侧边栏「个人的」这一层的容器），
    // 保证自动创建的容器页与用户已有页面并列、可见。
    final anchor = privates.firstWhereOrNull(
          (view) =>
              view.name == _kAnchorPageName && view.parentViewId.isNotEmpty,
        ) ??
        privates.firstWhereOrNull((view) => view.parentViewId.isNotEmpty);
    if (anchor == null) {
      return workspaceId;
    }
    final parentViewId = anchor.parentViewId;
    final created = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parentViewId,
      name: kFlashNoteContainerName,
      section: _section,
    );
    return created.fold((view) => view.id, (error) => parentViewId);
  }

  /// 生成 `DocumentDataPB` 的二进制字节（内核用 protobuf 解析 `initial_data`）。
  List<int> _buildInitialData(String body) {
    final document = Document.blank();
    final nodes = body
        .split('\n')
        .map((line) => paragraphNode(text: line))
        .toList(growable: false);
    document.insert([0], nodes);

    final data = DocumentDataPBFromTo.fromDocument(document);
    if (data == null) {
      throw Exception('生成文档数据失败');
    }
    return data.writeToBuffer();
  }

}
