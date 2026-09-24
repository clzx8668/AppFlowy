import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// 生活元数据块：心情 / 天气 / 位置。
///
/// **v1 方案：用内核已支持的 `callout` 块承载 + 自定义 payload**。
///
/// 为什么不用自定义节点类型（`life_meta`）：v0 实测虽然能插入渲染，但**重启后块丢失** ——
/// `Block.ty` 是 String 只说明存储结构能容纳，AppFlowy 文档的运行时写入/同步路径并不接受未知块类型。
/// 因此改用标准块 `callout`：节点类型内核确定支持，我们的数据写在它的 attributes（payload）里，
/// 由 App 侧覆写 `CalloutBlockKeys.type` 的构建器来渲染（带 `af_life_meta` 标记走我们的卡片，否则回退上游 callout）。
///
/// 数据落点：`af_life_meta` / `af_date` / `af_mood` / `af_weather` / `af_location` 全在 attributes 里，
/// 二进制资源不入库（蓝图要求）。
class LifeMetaBlockKeys {
  const LifeMetaBlockKeys._();

  /// 标记：这是一个生活元数据块（而不是普通 callout）。
  static const String markerKey = 'af_life_meta';
  static const String dateKey = 'af_date';
  static const String moodKey = 'af_mood';
  static const String weatherKey = 'af_weather';
  static const String locationKey = 'af_location';
}

/// 判断某个节点是否是我们扩展的生活元数据块。
bool isLifeMetaNode(Node node) =>
    node.attributes[LifeMetaBlockKeys.markerKey] == true;

/// 日期键工具（yyyy-MM-dd）。
String lifeMetaTodayKey() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
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
      node.attributes[LifeMetaBlockKeys.dateKey] as String? ??
          lifeMetaTodayKey();
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
