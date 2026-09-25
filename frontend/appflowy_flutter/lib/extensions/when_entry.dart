import 'dart:async';

import 'package:app_biz_store/app_biz_store.dart';
import 'package:app_diary_time/app_diary_time.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/callout/callout_block_component.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_backend/log.dart';

/// 「时间标记」：**标准 callout 块 + `af_when` payload**，用来给页面标注"这条内容属于哪一天"。
///
/// 为什么需要它（方案 5 的第三部分）：日历/时间线如果只看"最后编辑时间"，
/// 那么"今天补记昨天的事"会落到今天。把内容自己声明的时间写进块里，
/// 日历就能按 **内容时间** 归类，时间轴才真正贯穿全项目。
///
/// 与「生活记录」同一套形态：标准块类型 + JSON 安全属性 + 单节点单事务。
const String kWhenAttributeKey = 'af_when';

/// 节点工厂：callout + af_when（yyyy-MM-dd）。
Node whenMarkNode({String? date}) {
  final icon = EmojiIconData.emoji('🕒');
  final node = Node(
    type: CalloutBlockKeys.type,
    attributes: {
      CalloutBlockKeys.delta: Delta().toJson(),
      CalloutBlockKeys.icon: icon.emoji,
      // 必须写枚举名（String），详见 life_meta_callout_builder.dart 的坑说明
      CalloutBlockKeys.iconType: icon.type.name,
      kWhenAttributeKey: date ?? _todayKey(),
    },
  );
  return node;
}

String _todayKey() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

/// 在光标处插入「时间标记」块（一个事务只插一个节点）。
Future<void> insertWhenMark(EditorState editorState) async {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) {
    return;
  }
  final path = selection.end.path;
  final node = editorState.getNodeAtPath(path);
  final delta = node?.delta;
  if (node == null || delta == null) {
    return;
  }
  final insertedPath = delta.isEmpty ? path : path.next;
  final transaction = editorState.transaction
    ..insertNode(insertedPath, whenMarkNode())
    ..afterSelection = Selection.collapsed(Position(path: insertedPath));
  await editorState.apply(transaction);
}

/// 解析一篇文档里所有「时间标记」（页面 id → 日期列表）。
///
/// 日历加载时用它把"内容时间"算出来：同一页可以标多个时间（例如一次出差几天）。
Future<List<String>> collectWhenMarksOfDocument(String documentId) async {
  try {
    final result = await DocumentService().getDocument(documentId: documentId);
    final document = result.fold((s) => s.toDocument(), (f) => null);
    if (document == null) {
      return const [];
    }
    final dates = <String>[];
    for (final node in NodeIterator(
      document: document,
      startNode: document.root,
    ).toList()) {
      final value = node.attributes[kWhenAttributeKey];
      if (value is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
        if (!dates.contains(value)) {
          dates.add(value);
        }
      }
    }
    return dates;
  } catch (e) {
    Log.error('[时间标记] 解析失败 $documentId：$e');
    return const [];
  }
}

/// 把某页面的时间标记写进业务库索引表（`when_index`），供日历按内容时间归类。
Future<void> saveWhenMarks(String pageId, List<String> dates) async {
  try {
    final database = await _businessDatabase();
    final now = DateTime.now().millisecondsSinceEpoch;
    database.raw.execute('DELETE FROM when_index WHERE page_id = ?;', [pageId]);
    for (final date in dates) {
      database.raw.execute(
        'INSERT OR REPLACE INTO when_index (page_id, date_key, updated_at) '
        'VALUES (?, ?, ?);',
        [pageId, date, now],
      );
    }
  } catch (e) {
    Log.error('[时间标记] 写入索引失败 $pageId：$e');
  }
}

/// 读取全部"内容时间"索引：`yyyy-MM-dd` → 页面 id 列表。
Future<Map<String, List<String>>> loadWhenIndex() async {
  try {
    final database = await _businessDatabase();
    final rows = database.raw.select('SELECT page_id, date_key FROM when_index;');
    final byDay = <String, List<String>>{};
    for (final row in rows) {
      final pageId = row['page_id'] as String? ?? '';
      final dateKey = row['date_key'] as String? ?? '';
      if (pageId.isEmpty || dateKey.isEmpty) {
        continue;
      }
      byDay.putIfAbsent(dateKey, () => []).add(pageId);
    }
    return byDay;
  } catch (e) {
    Log.error('[时间标记] 读取索引失败：$e');
    return const {};
  }
}

Future<BusinessDatabase> _businessDatabase() async {
  final baseDirectory = await getIt<ApplicationDataStorage>().getPath();
  return BusinessDatabase.open(
    directory: baseDirectory,
    migrations: kDiaryMigrations,
  );
}
