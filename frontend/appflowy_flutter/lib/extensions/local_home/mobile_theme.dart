import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 手机端配色（对齐 `E:\Dev\moodiaryCRM` 的 `AppColor.themeColorList`）。
///
/// 做法：把参考项目的 6 套传统色 + PANTONE 摩卡做成"强调色"，
/// 用它生成 Material 3 的 `ColorScheme` 覆盖手机端外壳；
/// 选择结果存 `shared_preferences`（键 `mob_accent_index`），`-1` 表示跟随 AppFlowy 主题。
class MobPalette {
  const MobPalette._();

  static const List<({String name, Color color})> options = [
    (name: '百草霜', color: Color(0xFF303030)),
    (name: '群青', color: Color(0xFF2E59A7)),
    (name: '青黛', color: Color(0xFF45465E)),
    (name: '水朱华', color: Color(0xFFA72126)),
    (name: '芰荷', color: Color(0xFF4F794A)),
    (name: '缃叶', color: Color(0xFFECD452)),
    (name: '摩卡慕斯', color: Color(0xFFA47B67)),
  ];
}

/// 手机端主题色控制器（全局单例 + ValueNotifier，改动即时生效）。
class MobThemeController {
  const MobThemeController._();

  static const String _prefKey = 'mob_accent_index';

  /// 选中的配色下标；`null` = 跟随系统/AppFlowy 主题。
  static final ValueNotifier<int?> accentIndex = ValueNotifier<int?>(null);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getInt(_prefKey);
      if (value != null && value >= 0 && value < MobPalette.options.length) {
        accentIndex.value = value;
      } else {
        accentIndex.value = null;
      }
    } catch (_) {
      accentIndex.value = null;
    }
  }

  static Future<void> setIndex(int? index) async {
    accentIndex.value = index;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (index == null) {
        await prefs.remove(_prefKey);
      } else {
        await prefs.setInt(_prefKey, index);
      }
    } catch (_) {
      // 存不下也不影响本次会话生效
    }
  }
}

/// 用选中的配色包一层 Theme（只影响手机端外壳与我们的组件）。
class MobTheme extends StatelessWidget {
  const MobTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: MobThemeController.accentIndex,
      builder: (context, index, _) {
        if (index == null || index >= MobPalette.options.length) {
          return child;
        }
        final base = Theme.of(context);
        final scheme = ColorScheme.fromSeed(
          seedColor: MobPalette.options[index].color,
          brightness: base.brightness,
        );
        return Theme(
          data: base.copyWith(colorScheme: scheme),
          child: child,
        );
      },
    );
  }
}

/// 主题色选择弹层（设置页调用）。
Future<void> showMobPaletteSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('主题色', style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _swatch(sheetContext, null, '跟随系统'),
                for (var i = 0; i < MobPalette.options.length; i++)
                  _swatch(
                    sheetContext,
                    i,
                    MobPalette.options[i].name,
                    color: MobPalette.options[i].color,
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _swatch(
  BuildContext context,
  int? index,
  String label, {
  Color? color,
}) {
  final scheme = Theme.of(context).colorScheme;
  final selected = MobThemeController.accentIndex.value == index;
  return GestureDetector(
    onTap: () async {
      await MobThemeController.setIndex(index);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    },
    child: Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color ?? scheme.surfaceContainerHighest,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: color == null
              ? Icon(Icons.brightness_auto, color: scheme.onSurfaceVariant)
              : null,
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}
