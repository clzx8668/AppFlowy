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

  /// 全量实体索引（id → 实体）与按类型分组，用于关联展示与选择。
  Map<String, CrmEntity> _index = const {};
  Map<String, List<CrmEntity>> _byType = const {};

  /// 多对多关联 id（客户 ↔ 联系人）。
  List<String> _contactIds = const [];
  List<String> _customerIds = const [];

  /// 一对多派生列表（客户下的项目/合同/收款；项目下的合同/收款）。
  List<CrmEntity> _derivedProjects = const [];
  List<CrmEntity> _derivedContracts = const [];
  List<CrmEntity> _derivedReceivables = const [];

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

    // 关联数据：一次拉全量（个人使用量级很小），再在内存里索引
    final byType = <String, List<CrmEntity>>{};
    for (final type in CrmEntityType.all) {
      byType[type] = await widget.repository.list(type);
    }
    final index = <String, CrmEntity>{
      for (final list in byType.values)
        for (final item in list) item.id: item,
    };
    final contactIds = await widget.repository.relationsOf(
      fromType: entity.type,
      fromId: entity.id,
      toType: CrmEntityType.contact,
    );
    final customerIds = await widget.repository.relationsOf(
      fromType: entity.type,
      fromId: entity.id,
      toType: CrmEntityType.customer,
    );
    final derivedProjects = (byType[CrmEntityType.project] ?? const [])
        .where((p) => p.customerId == entity.id)
        .toList();
    final derivedContracts = (byType[CrmEntityType.contract] ?? const [])
        .where((c) => c.customerId == entity.id || c.projectId == entity.id)
        .toList();
    final derivedReceivables = (byType[CrmEntityType.receivable] ?? const [])
        .where(
          (r) => r.contractId == entity.id || r.projectId == entity.id ||
              r.customerId == entity.id,
        )
        .toList();
    if (!mounted) {
      return;
    }
    setState(() {
      _entity = entity;
      _events = events;
      _fieldDefs = defs;
      _links = links;
      _byType = byType;
      _index = index;
      _contactIds = contactIds;
      _customerIds = customerIds;
      _derivedProjects = derivedProjects;
      _derivedContracts = derivedContracts;
      _derivedReceivables = derivedReceivables;
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
                      // 负责人：个人使用场景默认隐藏（数据库列保留，便于将来多人协作）
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
                _relationsCard(theme, entity),
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

  // ------------------------------------------------------------ 关联区块

  /// 关联卡片：按实体类型给出该有的关联入口。
  ///
  /// - 客户：联系人（**多对多**）+ 项目/合同/收款（一对多，派生展示）
  /// - 联系人：所属客户（**多对多**）
  /// - 项目：客户（**一对一**）+ 合同（**一对一**）+ 联系人（多对多）
  /// - 合同：客户（一对一）+ 项目（一对一，若项目已有其它合同会提示）
  /// - 收款：合同（一对一 → 客户由合同带出）
  /// - 线索：客户（可选）+ 联系人（多对多）
  Widget _relationsCard(ThemeData theme, CrmEntity entity) {
    final rows = <Widget>[];

    void addRelationSection({
      required String title,
      required List<CrmEntity> items,
      String? addLabel,
      Future<void> Function()? onAdd,
      Future<void> Function(CrmEntity item)? onRemove,
    }) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '$title ${items.isEmpty ? '' : '(${items.length})'}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const Spacer(),
                  if (onAdd != null)
                    TextButton.icon(
                      onPressed: () => unawaited(onAdd()),
                      icon: const Icon(Icons.add, size: 16),
                      label: Text(addLabel ?? '添加'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
              if (items.isEmpty)
                Text(
                  '未关联',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outlineVariant,
                  ),
                )
              else
                for (final item in items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.link, size: 16),
                    title: Text(item.title.isEmpty ? '未命名' : item.title),
                    subtitle: item.stage.isEmpty
                        ? null
                        : Text(
                            item.stage,
                            style: theme.textTheme.labelSmall,
                          ),
                    onTap: () => unawaited(
                      openCrmEntity(context, item, widget.repository),
                    ),
                    trailing: onRemove == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => unawaited(onRemove(item)),
                          ),
                  ),
            ],
          ),
        ),
      );
    }

    switch (entity.type) {
      case CrmEntityType.customer:
      case CrmEntityType.lead:
        addRelationSection(
          title: '联系人',
          items: _contactIds
              .map((id) => _index[id])
              .whereType<CrmEntity>()
              .toList(),
          addLabel: '添加联系人',
          onAdd: () => _addRelation(entity, CrmEntityType.contact),
          onRemove: (item) => _removeRelation(
            entity,
            CrmEntityType.contact,
            item,
          ),
        );
        if (entity.type == CrmEntityType.lead) {
          final customer =
              entity.customerId.isEmpty ? null : _index[entity.customerId];
          addRelationSection(
            title: '客户',
            items: customer == null ? const [] : [customer],
            addLabel: '选择客户',
            onAdd: () => _pickForeignKey(
              entity,
              CrmEntityType.customer,
              (picked) => entity.copyWith(customerId: picked.id),
            ),
            onRemove: (_) async =>
                _save(entity.copyWith(customerId: '')),
          );
        }
        break;
      case CrmEntityType.contact:
        addRelationSection(
          title: '所属客户',
          items: _customerIds
              .map((id) => _index[id])
              .whereType<CrmEntity>()
              .toList(),
          addLabel: '添加客户',
          onAdd: () => _addRelation(entity, CrmEntityType.customer),
          onRemove: (item) => _removeRelation(
            entity,
            CrmEntityType.customer,
            item,
          ),
        );
        break;
      case CrmEntityType.project:
        final customer =
            entity.customerId.isEmpty ? null : _index[entity.customerId];
        addRelationSection(
          title: '客户（一对一）',
          items: customer == null ? const [] : [customer],
          addLabel: '选择客户',
          onAdd: () => _pickForeignKey(
            entity,
            CrmEntityType.customer,
            (picked) => entity.copyWith(customerId: picked.id),
          ),
          onRemove: (_) async => _save(entity.copyWith(customerId: '')),
        );
        addRelationSection(
          title: '合同（一对一）',
          items: _derivedContracts,
          addLabel: '选择合同',
          onAdd: () => _pickForeignKey(
            entity,
            CrmEntityType.contract,
            (picked) async {
              // 一对一：合同已有其它项目时提示
              if (picked.projectId.isNotEmpty &&
                  picked.projectId != entity.id) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('该合同已关联其它项目')),
                  );
                }
                return entity;
              }
              await widget.repository.upsert(
                picked.copyWith(
                  projectId: entity.id,
                  customerId: entity.customerId,
                  updatedAt: DateTime.now(),
                ),
              );
              return null;
            },
          ),
        );
        addRelationSection(
          title: '联系人',
          items: _contactIds
              .map((id) => _index[id])
              .whereType<CrmEntity>()
              .toList(),
          addLabel: '添加联系人',
          onAdd: () => _addRelation(entity, CrmEntityType.contact),
          onRemove: (item) => _removeRelation(
            entity,
            CrmEntityType.contact,
            item,
          ),
        );
        break;
      case CrmEntityType.contract:
        final project =
            entity.projectId.isEmpty ? null : _index[entity.projectId];
        final customer =
            entity.customerId.isEmpty ? null : _index[entity.customerId];
        addRelationSection(
          title: '项目（一对一）',
          items: project == null ? const [] : [project],
          addLabel: '选择项目',
          onAdd: () => _pickForeignKey(
            entity,
            CrmEntityType.project,
            (picked) async {
              final existing = (await widget.repository.listByColumn(
                type: CrmEntityType.contract,
                column: 'project_id',
                value: picked.id,
              ))
                  .where((c) => c.id != entity.id)
                  .toList();
              if (existing.isNotEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('该项目已关联其它合同')),
                  );
                }
                return entity;
              }
              return entity.copyWith(
                projectId: picked.id,
                customerId: picked.customerId.isEmpty
                    ? entity.customerId
                    : picked.customerId,
              );
            },
          ),
          onRemove: (_) async => _save(entity.copyWith(projectId: '')),
        );
        addRelationSection(
          title: '客户',
          items: customer == null ? const [] : [customer],
          addLabel: '选择客户',
          onAdd: () => _pickForeignKey(
            entity,
            CrmEntityType.customer,
            (picked) => entity.copyWith(customerId: picked.id),
          ),
          onRemove: (_) async => _save(entity.copyWith(customerId: '')),
        );
        break;
      case CrmEntityType.receivable:
        final contract =
            entity.contractId.isEmpty ? null : _index[entity.contractId];
        addRelationSection(
          title: '合同',
          items: contract == null ? const [] : [contract],
          addLabel: '选择合同',
          onAdd: () => _pickForeignKey(
            entity,
            CrmEntityType.contract,
            (picked) => entity.copyWith(
              contractId: picked.id,
              projectId: picked.projectId,
              customerId: picked.customerId,
            ),
          ),
          onRemove: (_) async => _save(entity.copyWith(contractId: '')),
        );
        break;
    }

    // 一对多派生列表（客户 → 项目 / 合同 / 收款）
    if (entity.type == CrmEntityType.customer) {
      addRelationSection(title: '项目（多期）', items: _derivedProjects);
      addRelationSection(title: '合同', items: _derivedContracts);
      addRelationSection(title: '收款', items: _derivedReceivables);
    } else if (entity.type == CrmEntityType.project) {
      addRelationSection(title: '收款', items: _derivedReceivables);
    } else if (entity.type == CrmEntityType.contract) {
      addRelationSection(title: '收款', items: _derivedReceivables);
    }

    return MobCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '关联',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          ...rows,
        ],
      ),
    );
  }

  /// 多对多：加一条关联（客户 ↔ 联系人）。
  Future<void> _addRelation(CrmEntity entity, String toType) async {
    final picked = await _pickEntity(toType);
    if (picked == null) {
      return;
    }
    await widget.repository.linkEntities(
      fromType: entity.type,
      fromId: entity.id,
      toType: toType,
      toId: picked.id,
    );
    await _reload();
  }

  Future<void> _removeRelation(
    CrmEntity entity,
    String toType,
    CrmEntity item,
  ) async {
    await widget.repository.unlinkEntities(
      fromType: entity.type,
      fromId: entity.id,
      toType: toType,
      toId: item.id,
    );
    await _reload();
  }

  /// 单向外键：选择某个实体后套用返回的更新（返回 null 表示不修改）。
  Future<void> _pickForeignKey(
    CrmEntity entity,
    String toType,
    // 允许同步返回（如直接给客户外键）或异步返回（需要先查重的场景）
    FutureOr<CrmEntity?> Function(CrmEntity picked) apply,
  ) async {
    final picked = await _pickEntity(toType);
    if (picked == null) {
      return;
    }
    final updated = await apply(picked);
    if (updated != null) {
      await _save(updated);
    } else {
      await _reload();
    }
  }

  /// 选择某个类型的实体（底部弹层）。
  Future<CrmEntity?> _pickEntity(String type) async {
    final items = _byType[type] ?? const <CrmEntity>[];
    if (items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('还没有${CrmEntityType.label(type)}，先去创建')),
        );
      }
      return null;
    }
    return showModalBottomSheet<CrmEntity>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.6,
          child: ListView(
            children: [
              for (final item in items)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.business_outlined),
                  title: Text(item.title.isEmpty ? '未命名' : item.title),
                  subtitle: item.subtitle.isEmpty
                      ? null
                      : Text(item.subtitle),
                  onTap: () => Navigator.of(sheetContext).pop(item),
                ),
            ],
          ),
        ),
      ),
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

/// 打开任意 CRM 实体详情（关联列表里点击跳转用）。
Future<void> openCrmEntity(
  BuildContext context,
  CrmEntity entity,
  CrmEntityRepository repository,
) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CrmEntityDetailPage(
        entityId: entity.id,
        repository: repository,
      ),
    ),
  );
}
