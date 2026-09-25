import 'dart:convert';

import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/domain/database_view_service.dart';
import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart'
    show FieldType, FieldPB;
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';

/// 时间线事件类型（写进「时间线」数据库的「类型」列）。
class TimelineKind {
  const TimelineKind._();

  static const String flashNote = '闪念';
  static const String diary = '日记';
  static const String workLog = '工作记录';
  static const String crm = 'CRM';
  static const String aiChat = 'AI 交流';
  static const String note = '笔记';
}

/// 时间线数据库页名（放在「日历」分类容器下）。
const String kTimelinePageName = '时间线';

const String _dateFieldName = '日期';
const String _kindFieldName = '类型';
const String _sourceFieldName = '来源';

/// 进程内缓存（避免每次写入都去建库/查字段）。
String? _timelineViewId;
FieldPB? _dateField;
FieldPB? _kindField;
FieldPB? _sourceField;
FieldPB? _primaryField;

/// 时间线是否已就绪（未就绪时 [recordTimelineEvent] 静默跳过，不影响主流程）。
bool get isTimelineReady => _timelineViewId != null && _dateField != null;

String? get timelineViewId => _timelineViewId;

/// 确保「时间线」数据库页存在（幂等），并准备字段；返回页面 id。
///
/// 为什么用**原生 Grid 数据库**：上游自带 Grid / 看板 / 日历 三种视图（手机端也有），
/// 我们只需要保证"每条内容都往这张表里写一行带日期的事件"，
/// 时间线/日历/看板的展示能力就全部白拿，不用自研视图。
Future<String?> ensureTimelinePage({required String parentViewId}) async {
  if (_timelineViewId != null) {
    return _timelineViewId;
  }
  try {
    String? existingId;
    final children =
        await ViewBackendService.getChildViews(viewId: parentViewId);
    for (final view in children.toNullable() ?? const <ViewPB>[]) {
      if (view.name == kTimelinePageName && view.layout == ViewLayoutPB.Grid) {
        existingId = view.id;
        break;
      }
    }
    existingId ??= (await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Grid,
      parentViewId: parentViewId,
      name: kTimelinePageName,
    ))
        .toNullable()
        ?.id;

    if (existingId == null || existingId.isEmpty) {
      Log.error('[时间线] 创建「$kTimelinePageName」数据库页失败');
      return null;
    }
    _timelineViewId = existingId;
    await _prepareFields(existingId);
    Log.info('[时间线] 就绪：$existingId');
    return existingId;
  } catch (e) {
    Log.error('[时间线] 初始化失败：$e');
    return null;
  }
}

/// 准备字段：日期（DateTime，日历视图必需）/ 类型 / 来源，并取得主字段（标题）。
Future<void> _prepareFields(String viewId) async {
  final database =
      (await DatabaseViewBackendService(viewId: viewId).openDatabase())
          .toNullable();
  final fields = <FieldPB>[
    for (final field in database?.fields ?? const [])
      if (field is FieldPB) field,
  ];

  FieldPB? find(String name) {
    for (final field in fields) {
      if (field.name == name) {
        return field;
      }
    }
    return null;
  }

  _dateField = find(_dateFieldName) ??
      (await FieldBackendService.createField(
        viewId: viewId,
        fieldType: FieldType.DateTime,
        fieldName: _dateFieldName,
      ))
          .toNullable();
  _kindField = find(_kindFieldName) ??
      (await FieldBackendService.createField(
        viewId: viewId,
        fieldName: _kindFieldName,
      ))
          .toNullable();
  _sourceField = find(_sourceFieldName) ??
      (await FieldBackendService.createField(
        viewId: viewId,
        fieldName: _sourceFieldName,
      ))
          .toNullable();
  _primaryField =
      (await FieldBackendService.getPrimaryField(viewId: viewId)).toNullable();
}

/// 记录一条时间线事件（各模块的统一写入点）。
///
/// - [date]：事件时间（日记=当天；闪念/工作记录/CRM=创建时间）
/// - [kind]：见 [TimelineKind]
/// - [title]：展示在日历/看板卡片上的标题（写进主字段）
/// - [sourceViewId]：来源页面 id（写进「来源」列，便于后续关联跳转）
Future<void> recordTimelineEvent({
  required DateTime date,
  required String kind,
  String title = '',
  String sourceViewId = '',
}) async {
  final viewId = _timelineViewId;
  final dateField = _dateField;
  if (viewId == null || dateField == null) {
    return;
  }
  try {
    await RowBackendService.createRow(
      viewId: viewId,
      withCells: (builder) {
        builder.insertDate(FieldInfo.initial(dateField), date);
        final kindField = _kindField;
        if (kindField != null) {
          builder.insertText(
            FieldInfo.initial(kindField),
            _richTextCellValue(kind),
          );
        }
        final primary = _primaryField;
        if (primary != null) {
          // 标题里带类型：Grid / 看板 / 日历卡片都直接看得到"这条属于哪一类"
          // （另外两列 类型/来源 仍会尝试写入，作为可筛选字段保留）
          final label = title.isEmpty ? kind : '$kind · $title';
          builder.insertText(
            FieldInfo.initial(primary),
            label,
          );
        }
        final sourceField = _sourceField;
        if (sourceField != null && sourceViewId.isNotEmpty) {
          builder.insertText(
            FieldInfo.initial(sourceField),
            _richTextCellValue(sourceViewId),
          );
        }
      },
    );
  } catch (e) {
    Log.error('[时间线] 写入事件失败（忽略）：$e');
  }
}

/// 非主字段的 RichText 单元格要写 **delta JSON**（主字段/行标题才接受纯文本）。
/// 上游 `TextCellDataPersistence` 保存的就是 delta 字符串，这里保持一致。
String _richTextCellValue(String text) => jsonEncode([
      {'insert': text},
    ]);
