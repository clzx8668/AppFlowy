import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// CRM 通用**带格式输入框**集合。
///
/// 设计要点（对齐产品要求）：
/// - **右侧常驻**：单位（元 / % / 月…）与字数（12/50）始终显示在输入框右侧，浅色弱化；
/// - **日期与时间自动分隔**：日期显示 `2026-09-25`，日期时间显示 `2026-09-25  ⏰ 14:30`
///   （日期、时间分别选择、分别成段，不会糊成一串数字）；
/// - **格式约束**：电话按 3-4-4 分组、只允许数字且最多 11 位；邮箱限制空白字符并做格式校验；
/// - 所有提示（hint / 单位 / 字数 / 校验）都是**浅色**样式，不抢正文。
class CrmInputStyles {
  const CrmInputStyles._();

  /// 浅色辅助文字（单位、字数、占位、校验）。
  static TextStyle? hint(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          );
}

/// 把数字按 3-4-4 分组（手机号观感），自动去掉非数字。
class PhoneInputFormatter extends TextInputFormatter {
  const PhoneInputFormatter({this.maxDigits = 11});

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final clipped =
        digits.length > maxDigits ? digits.substring(0, maxDigits) : digits;
    final buffer = StringBuffer();
    for (var i = 0; i < clipped.length; i++) {
      if (i == 3 || i == 7) {
        buffer.write(' ');
      }
      buffer.write(clipped[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// 通用文本/数字输入：右侧常驻单位与字数（浅色）。
class CrmTextField extends StatelessWidget {
  const CrmTextField({
    super.key,
    required this.controller,
    required this.label,
    this.unit,
    this.maxLength,
    this.numeric = false,
    this.keyboardType,
    this.inputFormatters,
    this.errorText,
    this.autofocus = false,
    this.hintText,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;

  /// 常驻右侧的单位（例如 元 / % / 月）。
  final String? unit;

  /// 有值时显示"已输入/上限"字数（浅色，始终可见）。
  final int? maxLength;
  final bool numeric;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? errorText;
  final bool autofocus;
  final String? hintText;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintStyle = CrmInputStyles.hint(context);
    return TextField(
      controller: controller,
      autofocus: autofocus,
      maxLines: maxLines,
      // 字数上限用 formatter 限制输入（不用 maxLength：Material 的计数器只在聚焦时淡入，
      // 我们要的是"右侧常驻"，所以自己在 suffix 里渲染，见下）。
      inputFormatters: [
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
        ...?inputFormatters,
      ],
      keyboardType: keyboardType ??
          (numeric ? const TextInputType.numberWithOptions(decimal: true) : null),
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        hintStyle: hintStyle,
        errorText: errorText,
        errorStyle: hintStyle?.copyWith(color: theme.colorScheme.error),
        // 右侧**常驻**：单位 + 字数，都是浅色；随输入实时更新。
        // 用 `suffix`（紧贴输入区）而不是 `suffixIcon`：后者在有约束时不显示。
        suffix: (unit == null || unit!.isEmpty) && maxLength == null
            ? null
            : ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => Padding(
                  padding: const EdgeInsets.only(left: 6, right: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (unit != null && unit!.isNotEmpty)
                        Text(unit!, style: hintStyle),
                      if (unit != null && unit!.isNotEmpty && maxLength != null)
                        const SizedBox(width: 8),
                      if (maxLength != null)
                        Text(
                          '${value.text.characters.length}/$maxLength',
                          style: hintStyle,
                        ),
                    ],
                  ),
                ),
              ),
        suffixStyle: hintStyle,
        counterStyle: hintStyle,
      ),
    );
  }
}

/// 电话输入：3-4-4 分组、最多 11 位、电话键盘。
class CrmPhoneField extends StatelessWidget {
  const CrmPhoneField({
    super.key,
    required this.controller,
    this.label = '电话',
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return CrmTextField(
      controller: controller,
      label: label,
      autofocus: autofocus,
      keyboardType: TextInputType.phone,
      inputFormatters: const [PhoneInputFormatter()],
      hintText: '138 0000 0000',
    );
  }
}

/// 邮箱输入：禁空白、邮箱键盘、非空时做格式校验（浅色提示）。
class CrmEmailField extends StatefulWidget {
  const CrmEmailField({
    super.key,
    required this.controller,
    this.label = '邮箱',
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;

  @override
  State<CrmEmailField> createState() => _CrmEmailFieldState();
}

class _CrmEmailFieldState extends State<CrmEmailField> {
  static final _pattern = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text.trim();
    final invalid = value.isNotEmpty && !_pattern.hasMatch(value);
    return CrmTextField(
      controller: widget.controller,
      label: widget.label,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.emailAddress,
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
      hintText: 'name@example.com',
      errorText: invalid ? '邮箱格式看起来不对' : null,
    );
  }
}

/// 日期 / 日期时间输入：点击选择，日期与时间**分段显示**（不会糊成一串数字）。
class CrmDateField extends StatelessWidget {
  const CrmDateField({
    super.key,
    required this.value,
    required this.onPick,
    this.label = '日期',
    this.withTime = false,
  });

  /// 当前值（null 表示未设置）。
  final DateTime? value;

  /// 点选后的回调（已经带时间）。
  final ValueChanged<DateTime?> onPick;
  final String label;

  /// true = 日期时间；false = 只到日期。
  final bool withTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintStyle = CrmInputStyles.hint(context);
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(6),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: Icon(
            withTime ? Icons.schedule : Icons.event_outlined,
            size: 18,
            color: theme.colorScheme.outline,
          ),
          suffixIconColor: theme.colorScheme.outline,
          helperText: withTime ? '日期与时间分段选择' : null,
          helperStyle: hintStyle,
        ),
        child: value == null
            ? Text('未设置', style: hintStyle)
            : _segments(theme, value!, withTime, hintStyle),
      ),
    );
  }

  Widget _segments(
    ThemeData theme,
    DateTime value,
    bool withTime,
    TextStyle? hintStyle,
  ) {
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${value.year}-${two(value.month)}-${two(value.day)}';
    final time = '${two(value.hour)}:${two(value.minute)}';
    if (!withTime) {
      return Text(date, style: theme.textTheme.bodyMedium);
    }
    return Row(
      children: [
        Text(date, style: theme.textTheme.bodyMedium),
        const SizedBox(width: 10),
        Text('|', style: hintStyle),
        const SizedBox(width: 10),
        Text(time, style: theme.textTheme.bodyMedium),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final initial = value ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) {
      onPick(null);
      return;
    }
    if (!withTime) {
      onPick(date);
      return;
    }
    if (!context.mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    onPick(
      DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? initial.hour,
        time?.minute ?? initial.minute,
      ),
    );
  }
}

/// 格式化输出（展示用）：日期 / 日期时间。
String formatCrmDate(DateTime time, {bool withTime = false}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final date = '${time.year}-${two(time.month)}-${two(time.day)}';
  if (!withTime) {
    return date;
  }
  return '$date  ${two(time.hour)}:${two(time.minute)}';
}

/// 解析 `yyyy-MM-dd` 或 `yyyy-MM-dd HH:mm`。
DateTime? parseCrmDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  final normalized = raw.trim().replaceFirst('  ', ' ');
  return DateTime.tryParse(normalized);
}
