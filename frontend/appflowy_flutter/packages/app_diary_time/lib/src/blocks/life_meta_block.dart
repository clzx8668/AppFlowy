import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 生活元数据块（自定义块，v0）：心情 / 天气 / 位置。
///
/// 关键事实（已核对内核源码 `collab-document/src/blocks/entities.rs`）：
/// `Block.ty` 是**字符串**、`Block.data` 是任意 JSON —— 因此自定义块类型可以安全落库、
/// 参与快照同步与全文检索，**不需要修改内核**（蓝图"自定义块只写 payload"的要求成立）。
///
/// 数据落点：全部写在节点的 attributes（= block.payload），二进制资源不入库。
class LifeMetaBlockKeys {
  const LifeMetaBlockKeys._();

  static const String type = 'life_meta';
  static const String dateKey = 'date';
  static const String moodKey = 'mood';
  static const String weatherKey = 'weather';
  static const String locationKey = 'location';
}

/// 创建一个生活元数据块节点（供斜杠菜单/程序化插入使用）。
Node lifeMetaBlockNode({
  String? date,
  String mood = '',
  String weather = '',
  String location = '',
}) {
  return Node(
    type: LifeMetaBlockKeys.type,
    attributes: {
      LifeMetaBlockKeys.dateKey: date ?? _todayKey(),
      LifeMetaBlockKeys.moodKey: mood,
      LifeMetaBlockKeys.weatherKey: weather,
      LifeMetaBlockKeys.locationKey: location,
    },
  );
}

String _todayKey() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

class LifeMetaBlockComponentBuilder extends BlockComponentBuilder {
  LifeMetaBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
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

  @override
  BlockComponentValidate get validate => (node) => true;
}

class LifeMetaBlockComponentWidget extends BlockComponentStatefulWidget {
  const LifeMetaBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<LifeMetaBlockComponentWidget> createState() =>
      _LifeMetaBlockComponentWidgetState();
}

class _LifeMetaBlockComponentWidgetState
    extends State<LifeMetaBlockComponentWidget> {
  // v0 不接入块选中（SelectableMixin 需要实现较多内部成员）；
  // 块本身可正常渲染、可编辑属性、可落库回读。
  BlockComponentConfiguration get configuration => widget.configuration;

  Node get node => widget.node;

  EditorState get editorState => context.read<EditorState>();

  String get _date =>
      node.attributes[LifeMetaBlockKeys.dateKey] as String? ?? _todayKey();
  String get _mood =>
      node.attributes[LifeMetaBlockKeys.moodKey] as String? ?? '';
  String get _weather =>
      node.attributes[LifeMetaBlockKeys.weatherKey] as String? ?? '';
  String get _location =>
      node.attributes[LifeMetaBlockKeys.locationKey] as String? ?? '';

  Future<void> _pick({
    required String title,
    required List<(String emoji, String label)> options,
    required String current,
    required String attributeKey,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final option in options)
                  ActionChip(
                    label: Text(
                      '${option.$1} ${option.$2}',
                      style: const TextStyle(fontSize: 15),
                    ),
                    backgroundColor: current == option.$1
                        ? Theme.of(sheetContext).colorScheme.primaryContainer
                        : null,
                    onPressed: () => Navigator.of(sheetContext).pop(option.$1),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (selected == null) {
      return;
    }
    await _updateAttribute(attributeKey, selected);
  }

  Future<void> _editLocation() async {
    final controller = TextEditingController(text: _location);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('地点'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如 济南 · 客户现场'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null) {
      return;
    }
    await _updateAttribute(LifeMetaBlockKeys.locationKey, value);
  }

  /// 通过 transaction 更新节点属性（= 写入 block payload），由编辑器统一提交给内核。
  Future<void> _updateAttribute(String key, Object value) async {
    final transaction = editorState.transaction
      ..updateNode(node, {key: value});
    await editorState.apply(transaction);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: configuration.padding(node),
      child: Material(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🌤️', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text(
                      _date,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '生活记录',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: Text(
                        _mood.isEmpty ? '😊 心情' : _mood,
                        style: const TextStyle(fontSize: 15),
                      ),
                      onPressed: () => _pick(
                        title: '心情',
                        options: kDiaryMoodOptions,
                        current: _mood,
                        attributeKey: LifeMetaBlockKeys.moodKey,
                      ),
                    ),
                    ActionChip(
                      label: Text(
                        _weather.isEmpty ? '⛅ 天气' : _weather,
                        style: const TextStyle(fontSize: 15),
                      ),
                      onPressed: () => _pick(
                        title: '天气',
                        options: kDiaryWeatherOptions,
                        current: _weather,
                        attributeKey: LifeMetaBlockKeys.weatherKey,
                      ),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.place_outlined, size: 16),
                      label: Text(
                        _location.isEmpty ? '地点' : _location,
                        style: const TextStyle(fontSize: 15),
                      ),
                      onPressed: _editLocation,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    );
  }
}

/// 心情候选（本包内定义，避免与 UI 层耦合）。
const List<(String emoji, String label)> kDiaryMoodOptions = [
  ('😄', '很好'),
  ('🙂', '不错'),
  ('😐', '一般'),
  ('😔', '低落'),
  ('😡', '生气'),
];

/// 天气候选。
const List<(String emoji, String label)> kDiaryWeatherOptions = [
  ('☀️', '晴'),
  ('🌤️', '多云'),
  ('☁️', '阴'),
  ('🌧️', '雨'),
  ('❄️', '雪'),
];

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
    handler: (editorState, _, __) async =>
        editorState.insertLifeMetaBlock(),
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
