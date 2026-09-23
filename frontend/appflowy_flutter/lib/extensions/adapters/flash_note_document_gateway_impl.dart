import 'package:app_flash_note/app_flash_note.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

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
    required this.parentViewId,
  });

  /// 闪念记录挂载的父视图（= 「闪念」容器页面 id）。
  final String parentViewId;

  @override
  Future<String> createDocument({
    required String title,
    required String body,
    required DateTime createdAt,
  }) async {
    // 首选：带正文创建（内核 initial_data 走 DocumentDataPB 二进制 protobuf）。
    final withContent = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parentViewId,
      name: title,
      initialDataBytes: _buildInitialData(body),
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
    );
    return titleOnly.fold(
      (view) => view.id,
      (error) => throw Exception('创建页面失败：${error.msg}'),
    );
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
