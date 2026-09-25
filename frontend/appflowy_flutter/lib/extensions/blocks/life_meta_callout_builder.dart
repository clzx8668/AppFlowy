import 'dart:convert';

import 'package:app_diary_time/app_diary_time.dart';
import 'package:appflowy/extensions/when_entry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/callout/callout_block_component.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 临时对照探针：插入我们的生活记录块之前，先插一个**上游原生 callout**。
///
/// 用途：在同一篇文档里同时验证
///   1) 原生 callout 能否落库（排除"callout 类型本身不被内核接受"）；
///   2) 带 `af_life_meta` payload 的 callout 能否落库（我们的目标）。
///
/// 2026-09-24 实测结论：探针块（原生 callout）落库 ✔、带 payload 的 callout 属性丢失 ✗ ——
/// 根因见下方 [lifeMetaBlockNode] 的注释（`icon_type` 写成枚举导致整张属性表编码失败）。
/// 探针已完成使命，保持 false。
const bool kLifeMetaInsertProbe = false;

/// 创建一个生活元数据块节点：**标准 `callout` 类型** + 我们的 payload。
///
/// 为什么用 callout 承载：自定义节点类型在 v0 实测"重启后丢失"（内核同步路径不接受未知块类型），
/// 而 callout 是内核已支持的标准块，落库/同步安全；我们的数据写在它的 attributes 里。
///
/// ⚠️ 关键坑（2026-09-24 实测定位）：属性表在写入内核前会被 `document_data_pb_extension.dart`
/// 的 `_dataAdapter` 做一次 `jsonEncode`，**只要有一个属性值不能被 JSON 编码，整个属性表就被
/// 降级成 `{}`**（异常被它 catch 后静默吞掉）。上游 `calloutNode()` 把 `icon_type` 写成
/// `FlowyIconType` 枚举对象，正好踩到这个坑：块能渲染、重启后只剩一个空 callout，
/// 我们的 `af_*` payload 也一起被丢掉。
/// 因此这里所有属性必须是 JSON 可编码的原始值 —— 枚举必须写 `.name`（读取端
/// `CalloutBlockComponentBuilder.emoji` 用的正是 `FlowyIconType.values.byName(type)`）。
Node lifeMetaBlockNode({
  String? date,
  String mood = '',
  String weather = '',
  String location = '',
}) {
  final icon = EmojiIconData.emoji('🌤️');
  final node = Node(
    type: CalloutBlockKeys.type,
    attributes: {
      CalloutBlockKeys.delta: Delta().toJson(),
      CalloutBlockKeys.icon: icon.emoji,
      // 必须写枚举名（String），不能写枚举对象：否则 jsonEncode 抛错 → 整张属性表被丢弃
      CalloutBlockKeys.iconType: icon.type.name,
      // 扩展 payload
      LifeMetaBlockKeys.markerKey: true,
      LifeMetaBlockKeys.dateKey: date ?? lifeMetaTodayKey(),
      LifeMetaBlockKeys.moodKey: mood,
      LifeMetaBlockKeys.weatherKey: weather,
      LifeMetaBlockKeys.locationKey: location,
    },
  );

  // 防御性自检：一旦有人再往里塞枚举/自定义对象，这里会在 debug 构建里立刻报错，
  // 而不是让内核侧静默丢属性（见上面的坑说明）。
  assert(() {
    try {
      jsonEncode(node.attributes);
      return true;
    } catch (error) {
      throw StateError(
        'life meta block attributes must be JSON encodable, got $error',
      );
    }
  }());

  return node;
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
  ///
  /// **必须逐个节点、逐个事务插入**：App 侧把编辑器的 transaction 翻译成内核块动作时
  /// （`editor_transaction_adapter.dart` 的 `InsertOperation.toBlockAction`），会用
  /// `prevId = getNodeAtPath(currentPath.previous)` 计算兄弟前驱；如果同一个事务里连续插入多个节点，
  /// 第二个节点的 previous 路径在**尚未更新**的文档里并不存在，`prevId` 变成空串并触发断言，
  /// 于是整批块动作根本没发给内核 —— 表现就是"块能渲染、重启后消失"。
  /// 上游自己的块插入（如数学公式）也都是一个事务只插一个节点。
  Future<void> insertLifeMetaBlockAt(Selection selection) async {
    final path = selection.end.path;
    final node = getNodeAtPath(path);
    final delta = node?.delta;
    if (node == null || delta == null) {
      return;
    }
    final isEmptyBlock = delta.isEmpty;
    var target = isEmptyBlock ? path : path.next;

    if (kLifeMetaInsertProbe) {
      // 对照块：上游原生 callout（无自定义 payload）
      await _insertNodeOnce(target, calloutNode(delta: Delta()));
      target = target.next;
    }

    // 我们的生活记录块：标准 callout + af_life_meta payload
    await _insertNodeOnce(target, lifeMetaBlockNode());
    final lifeMetaPath = target;
    target = target.next;

    // 补一个空段落便于继续输入
    await _insertNodeOnce(target, paragraphNode());

    if (isEmptyBlock) {
      // 原来的空段落已被我们顶到下方，删掉它，避免多出一个空行
      await apply(transaction..deleteNode(node));
    }

    selection = Selection.collapsed(Position(path: target));
    debugPrint(
      '[LIFEMETA] inserted at $lifeMetaPath, ops per transaction: 1',
    );
  }

  Future<void> _insertNodeOnce(Path path, Node node) async {
    try {
      final transaction = this.transaction..insertNode(path, node);
      await apply(transaction);
    } catch (error, stack) {
      debugPrint('[LIFEMETA] insert failed at $path: $error\n$stack');
      rethrow;
    }
  }
}

/// 覆写 `callout` 块的构建器：
/// 「时间标记」块的渲染：紧凑一行（🕒 日期 + 说明），点一下可以改日期。
class WhenMarkBlockComponentWidget extends BlockComponentStatefulWidget {
  const WhenMarkBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<WhenMarkBlockComponentWidget> createState() =>
      _WhenMarkBlockComponentWidgetState();
}

class _WhenMarkBlockComponentWidgetState
    extends State<WhenMarkBlockComponentWidget> {
  Node get node => widget.node;

  EditorState get editorState => context.read<EditorState>();

  String get _date => node.attributes[kWhenAttributeKey] as String? ?? '';

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return;
    }
    String two(int v) => v.toString().padLeft(2, '0');
    final value = '${picked.year}-${two(picked.month)}-${two(picked.day)}';
    final transaction = editorState.transaction
      ..updateNode(node, {kWhenAttributeKey: value});
    await editorState.apply(transaction);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: widget.configuration.padding(node),
      child: InkWell(
        onTap: _pickDate,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              const Text('🕒', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                _date.isEmpty ? '未设置时间' : _date,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '内容时间（日历按它归类）',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    // 二次开发：「时间标记」块（callout + af_when）也走我们的构建器，
    // 渲染成一行紧凑的时间标签，而不是默认的 callout 大卡片。
    if (node.attributes[kWhenAttributeKey] is String) {
      return WhenMarkBlockComponentWidget(
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
