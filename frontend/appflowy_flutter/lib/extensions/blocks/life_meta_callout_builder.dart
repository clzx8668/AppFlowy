import 'package:app_diary_time/app_diary_time.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/callout/callout_block_component.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// 创建一个生活元数据块节点：**标准 `callout` 类型** + 我们的 payload。
///
/// 为什么用 callout 承载：自定义节点类型在 v0 实测"重启后丢失"（内核同步路径不接受未知块类型），
/// 而 callout 是内核已支持的标准块，落库/同步安全；我们的数据写在它的 attributes 里。
Node lifeMetaBlockNode({
  String? date,
  String mood = '',
  String weather = '',
  String location = '',
}) {
  final icon = EmojiIconData.emoji('🌤️');
  return Node(
    type: CalloutBlockKeys.type,
    attributes: {
      CalloutBlockKeys.delta: Delta().toJson(),
      CalloutBlockKeys.icon: icon.emoji,
      CalloutBlockKeys.iconType: icon.type,
      // 扩展 payload
      LifeMetaBlockKeys.markerKey: true,
      LifeMetaBlockKeys.dateKey: date ?? lifeMetaTodayKey(),
      LifeMetaBlockKeys.moodKey: mood,
      LifeMetaBlockKeys.weatherKey: weather,
      LifeMetaBlockKeys.locationKey: location,
    },
  );
}

/// 斜杠菜单项：插入「生活记录」块。
SelectionMenuItem lifeMetaSlashMenuItem() {
  return SelectionMenuItem(
    getName: () => '生活记录',
    keywords: const [
      'life',
      'meta',
      'mood',
      'weather',
      'location',
      '心情',
      '天气',
      '位置',
      '生活',
    ],
    handler: (editorState, _, __) async => editorState.insertLifeMetaBlock(),
    icon: (editorState, isSelected, style) => Icon(
      Icons.wb_sunny_outlined,
      size: 18,
      color: isSelected
          ? style.selectionMenuItemSelectedIconColor
          : style.selectionMenuItemIconColor,
    ),
  );
}

extension LifeMetaEditorStateExtension on EditorState {
  /// 在当前段落之后插入一个生活记录块，并补一个空段落便于继续输入。
  Future<void> insertLifeMetaBlock() async {
    final selection = this.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }
    await insertLifeMetaBlockAt(selection);
  }

  /// 在指定选区位置插入生活记录块（供移动端「+」面板使用）。
  Future<void> insertLifeMetaBlockAt(Selection selection) async {
    final path = selection.end.path;
    final node = getNodeAtPath(path);
    final delta = node?.delta;
    if (node == null || delta == null) {
      return;
    }
    final insertedPath = delta.isEmpty ? path : path.next;
    final transaction = this.transaction
      ..insertNode(insertedPath, lifeMetaBlockNode())
      ..insertNode(insertedPath.next, paragraphNode())
      ..afterSelection =
          Selection.collapsed(Position(path: insertedPath.next.next));
    await apply(transaction);
  }
}

/// 覆写 `callout` 块的构建器：
/// - 带 `af_life_meta` 标记 → 渲染我们自己的生活记录卡片（心情/天气/位置）；
/// - 其它 callout → 原样交回上游构建器，行为完全不变。
///
/// 这样自定义块**完全走内核已支持的标准块类型**（落库/同步安全），
/// 同时保留"块级 payload + 自定义渲染"的形态。
class LifeMetaCalloutBlockComponentBuilder extends BlockComponentBuilder {
  LifeMetaCalloutBlockComponentBuilder({
    required BlockComponentBuilder fallback,
    super.configuration,
  }) : _fallback = fallback {
    // 这些是基类的可变字段（Dart 不允许用 getter 覆写字段），在构造时转交上游实现
    showActions = fallback.showActions;
    actionBuilder = fallback.actionBuilder;
    actionTrailingBuilder = fallback.actionTrailingBuilder;
    validate = (node) =>
        isLifeMetaNode(node) ? true : fallback.validate(node);
  }

  final BlockComponentBuilder _fallback;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    if (!isLifeMetaNode(node)) {
      return _fallback.build(blockComponentContext);
    }
    return LifeMetaBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }
}
