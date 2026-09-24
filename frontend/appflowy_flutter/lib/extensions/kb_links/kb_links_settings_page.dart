import 'dart:async';

import 'package:app_kb_links/app_kb_links.dart';
import 'package:appflowy/extensions/kb_links_entry.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';

/// 双链索引管理页：看索引规模、一键重建（写入独立业务库，不动内核）。
class KbLinksSettingsPage extends StatefulWidget {
  const KbLinksSettingsPage({super.key});

  @override
  State<KbLinksSettingsPage> createState() => _KbLinksSettingsPageState();
}

class _KbLinksSettingsPageState extends State<KbLinksSettingsPage> {
  LinkService? _service;
  int _indexedDocs = 0;
  int _linkCount = 0;
  bool _loading = true;
  bool _busy = false;
  String _status = '';
  double? _progress;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final service = await createLinkService();
      final (docs, links) = await service.stats();
      if (!mounted) {
        return;
      }
      setState(() {
        _service = service;
        _indexedDocs = docs;
        _linkCount = links;
        _loading = false;
      });
    } catch (e) {
      Log.error('[双链] 初始化失败：$e');
      if (mounted) {
        setState(() {
          _status = '初始化失败：$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshStats() async {
    final service = _service;
    if (service == null) {
      return;
    }
    final (docs, links) = await service.stats();
    if (!mounted) {
      return;
    }
    setState(() {
      _indexedDocs = docs;
      _linkCount = links;
    });
  }

  Future<void> _rebuild() async {
    final service = _service;
    if (service == null || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _progress = 0;
      _status = '正在重建索引…';
    });
    try {
      final (docs, links) = await rebuildLinkIndex(
        service: service,
        onProgress: (done, total) {
          if (mounted && total > 0) {
            setState(() => _progress = done / total);
          }
        },
      );
      await _refreshStats();
      if (mounted) {
        setState(() {
          _status = '重建完成：索引 $docs 篇文档、$links 条引用';
          _progress = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = '重建失败：$e';
          _progress = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('知识库双链')),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('索引状态', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          '已索引文档：$_indexedDocs 篇\n引用总数：$_linkCount 条',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '打开任一文档时会自动刷新那篇的出链，所以日常使用不需要手动重建；'
                          '重建用于首次启用、或从别处恢复数据后补齐全库索引。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_progress != null) ...[
                  LinearProgressIndicator(value: _progress, minHeight: 3),
                  const SizedBox(height: 8),
                ],
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => unawaited(_rebuild()),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(_busy ? '正在重建…' : '重建双链索引'),
                ),
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(_status, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 20),
                Text(
                  '双链怎么用\n'
                  '· 在正文里输入 @ 选择要引用的页面（块引用则在块的「…」菜单里复制链接）；\n'
                  '· 被引用的页面底部会出现「反向链接」，点开即可跳回引用方；\n'
                  '· 引用关系只保存 id、标题与所在段落片段，正文仍在内核里。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    height: 1.6,
                  ),
                ),
              ],
            ),
    );
  }
}
