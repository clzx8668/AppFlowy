import 'dart:convert';

import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/material.dart';

/// 页面标签（"树为主 + 标签为辅"里的"标签"）。
///
/// 存储位置：页面自己的 `view.extra`（我们已有 `af_*` 命名空间），键为 `af_tags`。
/// 为什么不用独立数据表：
/// - 标签属于页面元数据，放在 extra 里**随内核同步/回收站/快照走**，两端都读得到；
/// - 不新增表、不改内核，删除页面时标签自然一起消失，没有"孤儿标签"要清理。
const String kPageTagsExtraKey = 'af_tags';

/// 读取某个页面的标签（解析失败返回空列表）。
List<String> tagsOfView(ViewPB view) {
  if (view.extra.isEmpty) {
    return const [];
  }
  try {
    final decoded = jsonDecode(view.extra);
    if (decoded is! Map) {
      return const [];
    }
    final raw = decoded[kPageTagsExtraKey];
    if (raw is List) {
      return raw.whereType<String>().where((t) => t.trim().isNotEmpty).toList();
    }
    return const [];
  } catch (_) {
    return const [];
  }
}

/// 读取标签（按 viewId 现查一次内核）。
Future<List<String>> loadPageTags(String viewId) async {
  final result = await ViewBackendService.getView(viewId);
  final view = result.toNullable();
  if (view == null) {
    return const [];
  }
  return tagsOfView(view);
}

/// 写入标签：**合并**原有 extra 的其它键，只覆盖 `af_tags`（不会破坏 emoji/容器标记等）。
Future<bool> savePageTags(String viewId, List<String> tags) async {
  final result = await ViewBackendService.getView(viewId);
  final view = result.toNullable();
  if (view == null) {
    return false;
  }
  Map<String, dynamic> extra = {};
  if (view.extra.isNotEmpty) {
    try {
      final decoded = jsonDecode(view.extra);
      if (decoded is Map) {
        extra = decoded.map((k, v) => MapEntry('$k', v));
      }
    } catch (_) {
      // 解析失败就当作没有额外元数据，避免因为脏数据写不进去
    }
  }

  final normalized = <String>[];
  for (final tag in tags) {
    final trimmed = tag.trim();
    if (trimmed.isNotEmpty && !normalized.contains(trimmed)) {
      normalized.add(trimmed);
    }
  }
  if (normalized.isEmpty) {
    extra.remove(kPageTagsExtraKey);
  } else {
    extra[kPageTagsExtraKey] = normalized;
  }

  final updated = await ViewBackendService.updateView(
    viewId: viewId,
    extra: jsonEncode(extra),
  );
  return updated.fold((_) => true, (_) => false);
}

/// 文档底部的「标签」区块：给当前页面打标签/取消标签。
///
/// 与「子页面」「反向链接」共用上游 `footer:` 插槽，不改编辑器内部实现。
class PageTagsSection extends StatefulWidget {
  const PageTagsSection({super.key, required this.pageId});

  final String pageId;

  @override
  State<PageTagsSection> createState() => _PageTagsSectionState();
}

class _PageTagsSectionState extends State<PageTagsSection> {
  List<String> _tags = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final tags = await loadPageTags(widget.pageId);
    if (!mounted) {
      return;
    }
    setState(() {
      _tags = tags;
      _loading = false;
    });
  }

  Future<void> _addTag() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '例如 重要 / 待跟进 / 客户A / 2026Q3',
          ),
          onSubmitted: (text) => Navigator.of(dialogContext).pop(text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (value == null || value.trim().isEmpty) {
      return;
    }
    final ok = await savePageTags(widget.pageId, [..._tags, value]);
    if (ok) {
      await _reload();
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('标签保存失败')));
    }
  }

  Future<void> _removeTag(String tag) async {
    final ok = await savePageTags(
      widget.pageId,
      _tags.where((t) => t != tag).toList(),
    );
    if (ok) {
      await _reload();
    } else {
      Log.error('[标签] 删除失败：$tag');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Icon(Icons.sell_outlined, size: 15, color: theme.colorScheme.outline),
          const SizedBox(width: 6),
          if (_tags.isEmpty)
            Text(
              '标签',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            )
          else
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final tag in _tags)
                    InputChip(
                      label: Text('#$tag'),
                      visualDensity: VisualDensity.compact,
                      onDeleted: () => _removeTag(tag),
                    ),
                ],
              ),
            ),
          if (_tags.isEmpty) const Spacer(),
          TextButton.icon(
            onPressed: _addTag,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加标签'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ],
      ),
    );
  }
}
