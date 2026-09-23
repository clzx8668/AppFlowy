import 'package:flutter/material.dart';

import '../flash_note_service.dart';

/// 闪念捕获页（v0）。
///
/// 目标：打开即输入、一个动作完成保存（"先记录，后整理"）。
/// 后续迭代（蓝图）：移动端下拉新建、全局悬浮速记按钮、Windows 全局快捷键与速记小窗。
class FlashNoteCapturePage extends StatefulWidget {
  const FlashNoteCapturePage({
    super.key,
    required this.service,
    this.autoCreateDocument = true,
  });

  final FlashNoteService service;

  /// 是否在捕获时同时落成内核文档。
  final bool autoCreateDocument;

  @override
  State<FlashNoteCapturePage> createState() => _FlashNoteCapturePageState();
}

class _FlashNoteCapturePageState extends State<FlashNoteCapturePage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late bool _createDocument = widget.autoCreateDocument;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.service.capture(text, createDocument: _createDocument);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('闪念'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 18, height: 1.5),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '想到什么，直接写下来…',
                ),
              ),
            ),
            Row(
              children: [
                Switch(
                  value: _createDocument,
                  onChanged: (value) =>
                      setState(() => _createDocument = value),
                ),
                const SizedBox(width: 4),
                const Expanded(
                  child: Text(
                    '同时落成知识库页面',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
