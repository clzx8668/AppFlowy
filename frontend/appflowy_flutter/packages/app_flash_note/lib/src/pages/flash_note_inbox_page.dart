import 'package:flutter/material.dart';

import '../flash_note.dart';
import '../flash_note_service.dart';
import 'flash_note_capture_page.dart';

/// 闪念收件箱（v0）：极速回看 + 一键整理。
///
/// - 列表按捕获时间倒序；已落成文档的条目显示"已在知识库"，可点开原文；
/// - 未落成文档的条目可"转入知识库"（走内核文档 API）；
/// - 归档/删除只作用于业务库，不动内核数据。
class FlashNoteInboxPage extends StatefulWidget {
  const FlashNoteInboxPage({
    super.key,
    required this.service,
    this.onOpenDocument,
  });

  final FlashNoteService service;

  /// 打开内核文档（由 App 层注入导航实现）。
  final void Function(String documentId)? onOpenDocument;

  @override
  State<FlashNoteInboxPage> createState() => _FlashNoteInboxPageState();
}

class _FlashNoteInboxPageState extends State<FlashNoteInboxPage> {
  List<FlashNote> _notes = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final notes = await widget.service.inbox();
    if (!mounted) {
      return;
    }
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  Future<void> _capture() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FlashNoteCapturePage(service: widget.service),
      ),
    );
    if (saved ?? false) {
      await _reload();
    }
  }

  Future<void> _promote(FlashNote note) async {
    try {
      final updated = await widget.service.promoteToDocument(note);
      await _reload();
      if (mounted && updated.hasDocument) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已落成知识库页面')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('转入失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('闪念收件箱'),
        actions: [
          // 同时提供标题栏入口：部分机型/外壳布局下 FAB 的命中区会被底部导航遮挡
          IconButton(
            onPressed: _capture,
            icon: const Icon(Icons.add),
            tooltip: '新闪念',
          ),
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      // 抬高一些，避免被 App 移动端底部导航栏遮挡
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 88),
        child: FloatingActionButton.extended(
          onPressed: _capture,
          icon: const Icon(Icons.add),
          label: const Text('新闪念'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _notes.isEmpty
              ? const _EmptyHint()
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: _notes.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _buildItem(context, _notes[index]),
                ),
    );
  }

  Widget _buildItem(BuildContext context, FlashNote note) {
    return ListTile(
      title: Text(
        note.text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, height: 1.4),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '${_formatTime(note.createdAt)}  ·  '
          '${note.hasDocument ? '已在知识库' : '仅记录'}',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
      onTap: () {
        final documentId = note.documentId;
        if (documentId != null && widget.onOpenDocument != null) {
          widget.onOpenDocument!(documentId);
        } else {
          _promote(note);
        }
      },
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          switch (value) {
            case 'promote':
              await _promote(note);
              break;
            case 'archive':
              await widget.service.archive(note);
              await _reload();
              break;
            case 'delete':
              await widget.service.delete(note);
              await _reload();
              break;
          }
        },
        itemBuilder: (_) => [
          if (!note.hasDocument)
            const PopupMenuItem(
              value: 'promote',
              child: Text('转入知识库'),
            ),
          const PopupMenuItem(value: 'archive', child: Text('归档')),
          const PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
    );
  }

  static String _formatTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bolt_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            '还没有闪念\n点右下角，随手记下第一个想法',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
