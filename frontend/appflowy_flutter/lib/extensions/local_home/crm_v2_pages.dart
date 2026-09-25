import 'dart:async';

import 'package:app_biz_store/app_biz_store.dart' hide Row;
import 'package:app_crm_biz/app_crm_biz.dart';
import 'package:appflowy/extensions/local_home/mobile_ui_kit.dart';
import 'package:appflowy/extensions/local_home/mob_sliding_tabs.dart';
import 'package:appflowy/extensions/local_home/crm_entity_detail_page.dart';
import 'package:appflowy/extensions/timeline_entry.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';

/// CRM 首页（v2）：线索 / 客户 / 联系人 / 项目 / 合同 / 收款 六个分类页。
///
/// 关系链：**线索 →（转项目）→ 项目 → 合同 → 收款**；
/// 客户与联系人互相独立、都可挂到项目上；阶段属于"线索/项目/合同/收款"，
/// 阶段变化与跟踪记录都会写进统一时间轴（于是出现在日历/时间线里）。
class CrmHomePage extends StatefulWidget {
  const CrmHomePage({super.key, required this.workspaceId});

  final String workspaceId;

  @override
  State<CrmHomePage> createState() => _CrmHomePageState();
}

class _CrmHomePageState extends State<CrmHomePage>
    with TickerProviderStateMixin {
  CrmEntityRepository? _repository;
  bool _loading = true;

  late final TabController _tabController = TabController(
    length: CrmEntityType.all.length,
    vsync: this,
  )..addListener(() => setState(() {}));

  final Map<String, List<CrmEntity>> _entities = {};

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final database = await _openDatabase();
      final repository = CrmEntityRepository(database);
      if (!mounted) {
        return;
      }
      setState(() => _repository = repository);
      await _migrateLegacyCustomers(database, repository);
      await _reload();
    } catch (e) {
      Log.error('[CRM] 初始化失败：$e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// 把 v1 的 `crm_customers` 迁移到通用实体表（只做一次，幂等）。
  Future<void> _migrateLegacyCustomers(
    BusinessDatabase database,
    CrmEntityRepository repository,
  ) async {
    try {
      final legacy = database.raw.select('SELECT * FROM $kCrmCustomerTable;');
      if (legacy.isEmpty) {
        return;
      }
      final existing = await repository.list(CrmEntityType.customer);
      final existingIds = {for (final entity in existing) entity.id};
      for (final row in legacy) {
        final id = row['id'] as String? ?? '';
        if (id.isEmpty || existingIds.contains(id)) {
          continue;
        }
        await repository.create(
          CrmEntity(
            id: id,
            type: CrmEntityType.customer,
            title: row['name'] as String? ?? '',
            subtitle: row['company'] as String? ?? '',
            owner: row['owner'] as String? ?? '',
            phone: row['phone'] as String? ?? '',
            note: row['note'] as String? ?? '',
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at'] as int? ?? 0,
            ),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(
              row['updated_at'] as int? ?? 0,
            ),
          ),
        );
      }
      Log.info('[CRM] 旧客户表迁移完成：${legacy.length} 条');
    } catch (e) {
      Log.error('[CRM] 旧客户迁移失败（忽略）：$e');
    }
  }

  Future<void> _reload() async {
    final repository = _repository;
    if (repository == null) {
      return;
    }
    for (final type in CrmEntityType.all) {
      _entities[type] = await repository.list(type);
    }
    if (!mounted) {
      return;
    }
    setState(() => _loading = false);
  }

  Future<void> _createEntity(String type) async {
    final repository = _repository;
    if (repository == null) {
      return;
    }
    final created = await showCrmEntitySheet(
      context: context,
      type: type,
      repository: repository,
    );
    if (created == null) {
      return;
    }
    // 新建实体也登记到统一时间轴（CRM 事件与日历打通）
    unawaited(
      recordTimelineEvent(
        date: created.eventTime ?? DateTime.now(),
        kind: TimelineKind.crm,
        title: '${CrmEntityType.label(type)} · ${created.title}',
      ),
    );
    await _reload();
    if (mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CrmEntityDetailPage(
            entityId: created.id,
            repository: repository,
          ),
        ),
      );
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRM'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '字段设置',
            icon: const Icon(Icons.tune),
            onSelected: (type) => unawaited(_openFieldDefs(type)),
            itemBuilder: (context) => [
              for (final type in CrmEntityType.all)
                PopupMenuItem(
                  value: type,
                  child: Text('${CrmEntityType.label(type)} · 自定义字段'),
                ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: MobSlidingTabs(
            controller: _tabController,
            labels: [
              for (final type in CrmEntityType.all) CrmEntityType.label(type),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading
            ? null
            : () => unawaited(
                  _createEntity(CrmEntityType.all[_tabController.index]),
                ),
        icon: const Icon(Icons.add),
        label: Text(
          '新建${CrmEntityType.label(CrmEntityType.all[_tabController.index])}',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : TabBarView(
              controller: _tabController,
              children: [
                for (final type in CrmEntityType.all) _entityList(theme, type),
              ],
            ),
    );
  }

  Widget _entityList(ThemeData theme, String type) {
    final entities = _entities[type] ?? const <CrmEntity>[];
    if (entities.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: theme.colorScheme.outlineVariant,
            ),
            const SizedBox(height: 12),
            Text(
              '还没有${CrmEntityType.label(type)}，点右下角新建',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: Mob.pagePadding,
        itemCount: entities.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final entity = entities[index];
          return MobCard(
            onTap: () async {
              final repository = _repository;
              if (repository == null) {
                return;
              }
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CrmEntityDetailPage(
                    entityId: entity.id,
                    repository: repository,
                  ),
                ),
              );
              await _reload();
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entity.title.isEmpty ? '未命名' : entity.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (entity.stage.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          entity.stage,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
                if (entity.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entity.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (entity.amount > 0)
                      Text(
                        '¥${entity.amount.toStringAsFixed(0)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (entity.amount > 0) const SizedBox(width: 8),
                    if (entity.eventTime != null)
                      Text(
                        _formatDate(entity.eventTime!),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const Spacer(),
                    Text(
                      _formatDate(entity.updatedAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 字段设置：为某类实体自定义字段（key/名称/类型/选项），值存在实体的 extra 里。
  Future<void> _openFieldDefs(String type) async {
    final repository = _repository;
    if (repository == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CrmFieldDefsPage(
          entityType: type,
          repository: repository,
        ),
      ),
    );
    await _reload();
  }
}

String _formatDate(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)}';
}

Future<BusinessDatabase> crmDatabase() async {
  final baseDirectory = await getIt<ApplicationDataStorage>().getPath();
  return BusinessDatabase.open(
    directory: baseDirectory,
    migrations: kCrmV2Migrations,
  );
}

Future<BusinessDatabase> _openDatabase() => crmDatabase();

/// 新建实体弹层（各类型共用，字段按类型裁剪）。
Future<CrmEntity?> showCrmEntitySheet({
  required BuildContext context,
  required String type,
  required CrmEntityRepository repository,
}) async {
  final titleController = TextEditingController();
  final subtitleController = TextEditingController();
  final amountController = TextEditingController();
  final phoneController = TextEditingController();
  final ownerController = TextEditingController();
  final noteController = TextEditingController();
  final stages = CrmEntityType.stages(type);
  var stage = stages.isEmpty ? '' : stages.first;
  DateTime? eventTime;
  final withAmount = type == CrmEntityType.project ||
      type == CrmEntityType.contract ||
      type == CrmEntityType.receivable;
  final withPhone = type == CrmEntityType.lead ||
      type == CrmEntityType.customer ||
      type == CrmEntityType.contact;

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
                '新建${CrmEntityType.label(type)}',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: switch (type) {
                    CrmEntityType.lead => '线索名称',
                    CrmEntityType.customer => '客户名称',
                    CrmEntityType.contact => '联系人姓名',
                    CrmEntityType.project => '项目名称',
                    CrmEntityType.contract => '合同名称',
                    _ => '收款单标题',
                  },
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: subtitleController,
                decoration: InputDecoration(
                  labelText: switch (type) {
                    CrmEntityType.contact => '所属客户 / 公司',
                    CrmEntityType.customer => '公司简称 / 行业',
                    CrmEntityType.project => '客户 / 项目地点',
                    CrmEntityType.contract => '客户 / 合同编号',
                    _ => '备注说明',
                  },
                ),
              ),
              if (withPhone) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: '电话'),
                ),
              ],
              if (withAmount) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '金额（元）'),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: ownerController,
                decoration: const InputDecoration(labelText: '负责人'),
              ),
              if (stages.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  '阶段',
                  style: Theme.of(sheetContext).textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in stages)
                      ChoiceChip(
                        label: Text(option),
                        selected: stage == option,
                        onSelected: (_) => setSheetState(() => stage = option),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('关键日期'),
                subtitle: Text(
                  eventTime == null ? '未设置（会用于日历联动）' : _formatDate(eventTime!),
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: sheetContext,
                    initialDate: eventTime ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setSheetState(() => eventTime = picked);
                  }
                },
              ),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '备注'),
              ),
              const SizedBox(height: 16),
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
  if (saved != true || titleController.text.trim().isEmpty) {
    return null;
  }
  return repository.createNew(
    type: type,
    title: titleController.text.trim(),
    subtitle: subtitleController.text.trim(),
    stage: stage,
    amount: double.tryParse(amountController.text.trim()) ?? 0,
    owner: ownerController.text.trim(),
    phone: phoneController.text.trim(),
    note: noteController.text.trim(),
    eventTime: eventTime,
  );
}
