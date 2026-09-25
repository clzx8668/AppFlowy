import 'dart:async';

import 'package:app_crm_biz/app_crm_biz.dart';
import 'package:appflowy/extensions/flash_note_entry.dart';
import 'package:appflowy/extensions/local_home/mobile_ui_kit.dart';
import 'package:appflowy/extensions/timeline_entry.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// CRM 实体详情（线索/客户/联系人/项目/合同/收款共用）。
///
/// 职责：核心字段编辑、阶段流转、跟踪记录（带时间 → 统一时间轴）、
/// 关联内核记录页（CRM 与首页记录打通）、线索转项目。
class CrmEntityDetailPage extends StatefulWidget {
  const CrmEntityDetailPage({
    super.key,
    required this.entityId,
    required this.repository,
  });

  final String entityId;
  final CrmEntityRepository repository;

  @override
  State<CrmEntityDetailPage> createState() => _CrmEntityDetailPageState();
}

class _CrmEntityDetailPageState extends State<CrmEntityDetailPage> {
  CrmEntity? _entity;
  List<CrmEvent> _events = const [];
  List<CrmFieldDef> _fieldDefs = const [];
  List<String> _links = const [];
  final Map<String, String> _linkTitles = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final entity = await widget.repository.get(widget.entityId);
    if (entity == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }
    final events = await widget.repository.eventsOf(entity.id);
    final defs = await widget.repository.fieldDefs(entity.type);
    final links = await widget.repository.linksOf(entity.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _entity = entity;
      _events = events;
      _fieldDefs = defs;
      _links = links;
      _loading = false;
    });
  }

  Future<void> _save(CrmEntity updated) async {
    await widget.repository.upsert(updated.copyWith(updatedAt: DateTime.now()));
    await _reload();
  }

  Future<void> _editText({
    required String label,
    required String current,
    required CrmEntity Function(CrmEntity, String) apply,
    bool multiline = false,
    TextInputType? keyboardType,
  }) async {
    final entity = _entity;
    if (entity == null) {
      return;
    }
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: multiline ? 5 : 1,
          keyboardType: keyboardType,
          decoration: InputDecoration(hintText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null) {
      return;
    }
    await _save(apply(entity, value.trim()));
  }

  /// 阶段流转：改阶段 + 写阶段事件 + 写统一时间轴（→ 日历/时间线）。
  Future<void> _changeStage(String stage) async {
    final entity = _entity;
    if (entity == null || entity.stage == stage) {
      return;
    }
    final from = entity.stage.isEmpty ? '—' : entity.stage;
    await _save(entity.copyWith(stage: stage));
    await widget.repository.addEvent(
      entityType: entity.type,
      entityId: entity.id,
      kind: '阶段',
      content: '阶段流转：$from → $stage',
    );
    await recordTimelineEvent(
      date: DateTime.now(),
      kind: TimelineKind.crm,
      title: '${entity.title} · $stage',
    );
    await _reload();
  }

  Future<void> _addEvent() async {
    final entity = _entity;
    if (entity == null) {
      return;
    }
    var kind = CrmEvent.kinds.first;
    var generatePage = false;
    var eventTime = DateTime.now();
    final controller = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '记录一次跟进',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final option in CrmEvent.kinds)
                      ChoiceChip(
                        label: Text(option),
                        selected: kind == option,
                        onSelected: (_) => setSheetState(() => kind = option),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: '内容',
                    hintText: '例如：现场沟通膜池尺寸，下周出方案',
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('时间'),
                  subtitle: Text(_formatDate(eventTime)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: sheetContext,
                      initialDate: eventTime,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setSheetState(() => eventTime = picked);
                    }
                  },
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: generatePage,
                  title: const Text('同时生成一篇记录（可在首页记录里继续写）'),
                  onChanged: (value) =>
                      setSheetState(() => generatePage = value ?? false),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true || controller.text.trim().isEmpty) {
      return;
    }
    final content = controller.text.trim();
    final event = await widget.repository.addEvent(
      entityType: entity.type,
      entityId: entity.id,
      content: content,
      kind: kind,
      eventTime: eventTime,
    );
    if (generatePage) {
      final viewId = await _createLinkedRecord(entity, '$kind：$content');
      if (viewId != null) {
        await widget.repository.updateEventLinkedView(
          eventId: event.id,
          viewId: viewId,
        );
      }
    }
    await recordTimelineEvent(
      date: eventTime,
      kind: TimelineKind.crm,
      title: '${entity.title} · $kind',
    );
    await _reload();
  }

  /// 生成一篇关联记录：落在「笔记」容器下（沿用内核页面树，可在首页记录里编辑）。
  Future<String?> _createLinkedRecord(CrmEntity entity, String body) async {
    try {
      final parentId = await _noteContainerId();
      if (parentId == null) {
        return null;
      }
      final created = await ViewBackendService.createView(
        layoutType: ViewLayoutPB.Document,
        parentViewId: parentId,
        name: '${entity.title} · ${_formatDate(DateTime.now())}',
        initialDataBytes: _initialData(body),
      );
      return created.toNullable()?.id;
    } catch (e) {
      Log.error('[CRM] 生成记录页失败：$e');
      return null;
    }
  }

  /// 找「笔记」分类容器（带 `af_module: note` 标记的顶层页面）。
  Future<String?> _noteContainerId() async {
    final result = await ViewBackendService.getAllViews();
    for (final view in result.toNullable()?.items ?? const <ViewPB>[]) {
      if (view.extra.contains('"af_container":true') &&
          view.extra.contains('"af_module":"note"')) {
        return view.id;
      }
    }
    return null;
  }

  List<int>? _initialData(String body) {
    try {
      final document = Document.blank();
      final nodes = body
          .split('\n')
          .map((line) => paragraphNode(text: line))
          .toList(growable: false);
      document.insert([0], nodes);
      return DocumentDataPBFromTo.fromDocument(document)?.writeToBuffer();
    } catch (e) {
      Log.error('[CRM] 生成初始正文失败：$e');
      return null;
    }
  }

  Future<void> _convertLeadToProject() async {
    final entity = _entity;
    if (entity == null) {
      return;
    }
    final project = await widget.repository.createNew(
      type: CrmEntityType.project,
      title: entity.title,
      subtitle: entity.subtitle,
      stage: CrmEntityType.stages(CrmEntityType.project).first,
      owner: entity.owner,
      note: entity.note,
      leadId: entity.id,
      customerId: entity.customerId,
      contactId: entity.contactId,
    );
    await _save(entity.copyWith(stage: '已转项目'));
    await widget.repository.addEvent(
      entityType: entity.type,
      entityId: entity.id,
      kind: '转项目',
      content: '线索已转为项目：${project.title}',
    );
    await recordTimelineEvent(
      date: DateTime.now(),
      kind: TimelineKind.crm,
      title: '线索转项目 · ${project.title}',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已生成项目「${project.title}」')),
      );
    }
    await _reload();
  }

  Future<void> _pickLink() async {
    final entity = _entity;
    if (entity == null) {
      return;
    }
    final result = await ViewBackendService.getAllViews();
    final views = (result.toNullable()?.items ?? const <ViewPB>[])
        .where((v) => v.layout == ViewLayoutPB.Document && v.name.isNotEmpty)
        .take(60)
        .toList();
    if (!mounted) {
      return;
    }
    final picked = await showModalBottomSheet<ViewPB>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.6,
          child: ListView(
            children: [
              for (final view in views)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(view.name),
                  onTap: () => Navigator.of(sheetContext).pop(view),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) {
      return;
    }
    await widget.repository.linkView(
      entityType: entity.type,
      entityId: entity.id,
      viewId: picked.id,
    );
    _linkTitles[picked.id] = picked.name;
    await _reload();
  }

  Future<void> _unlink(String viewId) async {
    final entity = _entity;
    if (entity == null) {
      return;
    }
    await widget.repository.unlinkView(entityId: entity.id, viewId: viewId);
    await _reload();
  }

  Future<void> _deleteEntity() async {
    final entity = _entity;
    if (entity == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除「${entity.title}」？'),
        content: const Text('该 CRM 记录会被删除（业务库数据）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await widget.repository.delete(entity.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entity = _entity;
    final stages =
        entity == null ? const <String>[] : CrmEntityType.stages(entity.type);
    return Scaffold(
      appBar: AppBar(
        title:
            Text(entity == null || entity.title.isEmpty ? 'CRM' : entity.title),
        actions: [
          if (entity?.type == CrmEntityType.lead)
            IconButton(
              tooltip: '转为项目',
              icon: const Icon(Icons.drive_file_move_outline),
              onPressed: () => unawaited(_convertLeadToProject()),
            ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => unawaited(_deleteEntity()),
          ),
        ],
      ),
      body: _loading || entity == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                MobCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fieldRow(
                        theme,
                        '标题',
                        entity.title,
                        () => _editText(
                          label: '标题',
                          current: entity.title,
                          apply: (c, v) => c.copyWith(title: v),
                        ),
                      ),
                      _fieldRow(
                        theme,
                        '摘要',
                        entity.subtitle,
                        () => _editText(
                                label: '摘要',
                                current: entity.subtitle,
                                apply: (c, v) => c.copyWith(subtitle: v),
                              ),
                      ),
                      _fieldRow(
                        theme,
                        '负责人',
                        entity.owner,
                        () => _editText(
                                label: '负责人',
                                current: entity.owner,
                                apply: (c, v) => c.copyWith(owner: v),
                              ),
                      ),
                      _fieldRow(
                        theme,
                        '电话',
                        entity.phone,
                        () => _editText(
                          label: '电话',
                          current: entity.phone,
                          keyboardType: TextInputType.phone,
                          apply: (c, v) => c.copyWith(phone: v),
                        ),
                      ),
                      _fieldRow(
                        theme,
                        '金额',
                        entity.amount > 0
                            ? '¥${entity.amount.toStringAsFixed(0)}'
                            : '',
                        () => _editText(
                          label: '金额（元）',
                          current:
                              entity.amount > 0 ? entity.amount.toString() : '',
                          keyboardType: TextInputType.number,
                          apply: (c, v) =>
                              c.copyWith(amount: double.tryParse(v) ?? 0),
                        ),
                      ),
                      _fieldRow(
                        theme,
                        '关键日期',
                        entity.eventTime == null
                            ? ''
                            : _formatDate(entity.eventTime!),
                        () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: entity.eventTime ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            await _save(entity.copyWith(eventTime: picked));
                            await recordTimelineEvent(
                              date: picked,
                              kind: TimelineKind.crm,
                              title: '${entity.title} · 关键日期',
                            );
                          }
                        },
                      ),
                      _fieldRow(
                        theme,
                        '备注',
                        entity.note,
                        () => _editText(
                          label: '备注',
                          current: entity.note,
                          multiline: true,
                          apply: (c, v) => c.copyWith(note: v),
                        ),
                      ),
                    ],
                  ),
                ),
                if (stages.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  MobCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '阶段',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final stage in stages)
                              ChoiceChip(
                                label: Text(stage),
                                selected: entity.stage == stage,
                                onSelected: (_) =>
                                    unawaited(_changeStage(stage)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                MobCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader(theme, '关联记录', '关联', _pickLink),
                      if (_links.isEmpty)
                        Text(
                          '还没有关联的页面（方案 / 会议记录都可以挂上来）',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        )
                      else
                        for (final viewId in _links)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.description_outlined),
                            title: Text(_linkTitles[viewId] ?? '打开页面'),
                            onTap: () => unawaited(
                              openDocumentByViewId(context, viewId),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () => unawaited(_unlink(viewId)),
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                MobCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '自定义字段',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (_fieldDefs.isEmpty)
                        Text(
                          '在 CRM 右上角「字段设置」里为这类实体定义字段',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        )
                      else
                        for (final def in _fieldDefs)
                          _fieldRow(
                            theme,
                            def.label.isEmpty ? def.key : def.label,
                            entity.extra[def.key] ?? '',
                            () => _editText(
                              label: def.label.isEmpty ? def.key : def.label,
                              current: entity.extra[def.key] ?? '',
                              apply: (c, v) => c.copyWith(
                                extra: {...c.extra, def.key: v},
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                MobCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader(theme, '跟踪记录', '记录跟进', _addEvent),
                      if (_events.isEmpty)
                        Text(
                          '还没有跟踪记录',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        )
                      else
                        for (final event in _events)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  _eventIcon(event.kind),
                                  size: 15,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_formatDate(event.eventTime)} · ${event.kind}',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: theme.colorScheme.outline,
                                        ),
                                      ),
                                      Text(
                                        event.content,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                      if (event.linkedViewId.isNotEmpty)
                                        InkWell(
                                          onTap: () => unawaited(
                                            openDocumentByViewId(
                                              context,
                                              event.linkedViewId,
                                            ),
                                          ),
                                          child: Text(
                                            '查看记录 ›',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: theme.colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.close, size: 15),
                                  onPressed: () async {
                                    await widget.repository
                                        .deleteEvent(event.id);
                                    await _reload();
                                  },
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionHeader(
    ThemeData theme,
    String title,
    String actionLabel,
    Future<void> Function() action,
  ) {
    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: () => unawaited(action()),
          icon: const Icon(Icons.add, size: 16),
          label: Text(actionLabel),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      ],
    );
  }

  Widget _fieldRow(
    ThemeData theme,
    String label,
    String value,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Mob.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value.isEmpty ? '未填写' : value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: value.isEmpty ? theme.colorScheme.outline : null,
                ),
              ),
            ),
            Icon(
              Icons.edit_outlined,
              size: 15,
              color: theme.colorScheme.outlineVariant,
            ),
          ],
        ),
      ),
    );
  }

  IconData _eventIcon(String kind) {
    switch (kind) {
      case '电话':
        return Icons.call_outlined;
      case '拜访':
        return Icons.directions_walk;
      case '会议':
        return Icons.groups_outlined;
      case '微信':
        return Icons.chat_bubble_outline;
      case '邮件':
        return Icons.mail_outline;
      case '阶段':
      case '转项目':
        return Icons.trending_up;
      default:
        return Icons.sticky_note_2_outlined;
    }
  }
}

/// 自定义字段定义管理：为某类实体增删字段（值存在实体 `extra`，不改表结构）。
class CrmFieldDefsPage extends StatefulWidget {
  const CrmFieldDefsPage({
    super.key,
    required this.entityType,
    required this.repository,
  });

  final String entityType;
  final CrmEntityRepository repository;

  @override
  State<CrmFieldDefsPage> createState() => _CrmFieldDefsPageState();
}

class _CrmFieldDefsPageState extends State<CrmFieldDefsPage> {
  List<CrmFieldDef> _defs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final defs = await widget.repository.fieldDefs(widget.entityType);
    if (!mounted) {
      return;
    }
    setState(() {
      _defs = defs;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final labelController = TextEditingController();
    final keyController = TextEditingController();
    var type = 'text';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新增字段'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                autofocus: true,
                decoration: const InputDecoration(labelText: '显示名称'),
              ),
              TextField(
                controller: keyController,
                decoration: const InputDecoration(
                  labelText: '字段 key（英文，唯一）',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: '类型'),
                items: const [
                  DropdownMenuItem(value: 'text', child: Text('文本')),
                  DropdownMenuItem(value: 'number', child: Text('数字')),
                  DropdownMenuItem(value: 'date', child: Text('日期')),
                  DropdownMenuItem(value: 'select', child: Text('单选')),
                ],
                onChanged: (v) => setDialogState(() => type = v ?? 'text'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) {
      return;
    }
    final key = keyController.text.trim();
    if (key.isEmpty) {
      return;
    }
    await widget.repository.upsertFieldDef(
      CrmFieldDef(
        entityType: widget.entityType,
        key: key,
        label: labelController.text.trim(),
        type: type,
        sortOrder: _defs.length,
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${CrmEntityType.label(widget.entityType)} · 自定义字段'),
        actions: [
          IconButton(
            tooltip: '新增字段',
            icon: const Icon(Icons.add),
            onPressed: () => unawaited(_add()),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Text(
                  '字段值存在实体自己的 extra 里 —— 新增字段不需要改数据库结构。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                if (_defs.isEmpty)
                  Text('还没有自定义字段', style: theme.textTheme.bodyMedium)
                else
                  for (final def in _defs)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(def.label.isEmpty ? def.key : def.label),
                      subtitle: Text('${def.key} · ${def.type}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await widget.repository
                              .deleteFieldDef(def.entityType, def.key);
                          await _reload();
                        },
                      ),
                    ),
              ],
            ),
    );
  }
}

String _formatDate(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)}';
}
