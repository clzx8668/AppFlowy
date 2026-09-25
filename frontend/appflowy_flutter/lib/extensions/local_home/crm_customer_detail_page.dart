import 'dart:async';

import 'package:app_biz_store/app_biz_store.dart' hide Row;
import 'package:app_crm_biz/app_crm_biz.dart';
import 'package:appflowy/extensions/local_home/mobile_ui_kit.dart';
import 'package:appflowy/extensions/timeline_entry.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';

/// CRM 客户详情：编辑档案、切换阶段、记录跟进、删除。
///
/// 数据在独立业务库（`crm_customers`）；"记录跟进"会往统一时间轴写一条事件，
/// 这样客户动态也会出现在日历/时间线里（蓝图：CRM 与记忆体系打通）。
class CrmCustomerDetailPage extends StatefulWidget {
  const CrmCustomerDetailPage({super.key, required this.customerId});

  final String customerId;

  @override
  State<CrmCustomerDetailPage> createState() => _CrmCustomerDetailPageState();
}

class _CrmCustomerDetailPageState extends State<CrmCustomerDetailPage> {
  CrmRepository? _repository;
  CrmCustomer? _customer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final baseDirectory = await getIt<ApplicationDataStorage>().getPath();
      final database = await BusinessDatabase.open(
        directory: baseDirectory,
        migrations: kCrmMigrations,
      );
      final repository = CrmRepositoryImpl(database);
      final customers = await repository.listCustomers();
      if (!mounted) {
        return;
      }
      setState(() {
        _repository = repository;
        _customer = customers.firstWhere(
          (c) => c.id == widget.customerId,
          orElse: () => customers.isEmpty
              ? CrmCustomer(
                  id: widget.customerId,
                  name: '',
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                )
              : customers.first,
        );
        _loading = false;
      });
    } catch (e) {
      Log.error('[CRM] 详情加载失败：$e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save(CrmCustomer updated) async {
    final repository = _repository;
    if (repository == null) {
      return;
    }
    await repository.updateCustomer(
      updated.copyWith(updatedAt: DateTime.now()),
    );
    if (!mounted) {
      return;
    }
    setState(() => _customer = updated);
  }

  Future<void> _editField({
    required String title,
    required String current,
    required CrmCustomer Function(CrmCustomer, String) apply,
    bool multiline = false,
    TextInputType? keyboardType,
  }) async {
    final customer = _customer;
    if (customer == null) {
      return;
    }
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: multiline ? 5 : 1,
          keyboardType: keyboardType,
          decoration: InputDecoration(hintText: title),
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
    await _save(apply(customer, value.trim()));
  }

  /// 记录一次跟进：写统一时间轴（kind=CRM），并在备注里追加一行流水。
  Future<void> _logFollowUp() async {
    final customer = _customer;
    if (customer == null) {
      return;
    }
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('记录一次跟进'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: '例如：电话沟通了方案细节，下周现场汇报',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (content == null || content.trim().isEmpty) {
      return;
    }
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}';
    final note = customer.note.isEmpty
        ? '$stamp  $content'
        : '${customer.note}\n$stamp  $content';
    await _save(customer.copyWith(note: note));
    await recordTimelineEvent(
      date: now,
      kind: TimelineKind.crm,
      title: '${customer.name} · ${content.trim()}',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已记录跟进，并写入时间线')),
      );
    }
  }

  Future<void> _delete() async {
    final customer = _customer;
    final repository = _repository;
    if (customer == null || repository == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除客户「${customer.name}」？'),
        content: const Text('客户档案会被删除（业务库数据，不可从回收站恢复）。'),
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
    await repository.deleteCustomer(customer.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = _customer;
    return Scaffold(
      appBar: AppBar(
        title: Text(customer?.name.isEmpty ?? true ? '客户' : customer!.name),
        actions: [
          IconButton(
            tooltip: '删除客户',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: _loading || customer == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                MobCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fieldTile(
                        theme,
                        label: '姓名',
                        value: customer.name,
                        onTap: () => _editField(
                          title: '姓名',
                          current: customer.name,
                          apply: (c, v) => c.copyWith(name: v),
                        ),
                      ),
                      _fieldTile(
                        theme,
                        label: '公司',
                        value: customer.company,
                        onTap: () => _editField(
                          title: '公司',
                          current: customer.company,
                          apply: (c, v) => c.copyWith(company: v),
                        ),
                      ),
                      _fieldTile(
                        theme,
                        label: '负责人',
                        value: customer.owner,
                        onTap: () => _editField(
                          title: '负责人',
                          current: customer.owner,
                          apply: (c, v) => c.copyWith(owner: v),
                        ),
                      ),
                      _fieldTile(
                        theme,
                        label: '电话',
                        value: customer.phone,
                        onTap: () => _editField(
                          title: '电话',
                          current: customer.phone,
                          keyboardType: TextInputType.phone,
                          apply: (c, v) => c.copyWith(phone: v),
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
                          for (final stage in kCrmStages)
                            ChoiceChip(
                              label: Text(stage),
                              selected: customer.stage == stage,
                              onSelected: (_) =>
                                  unawaited(_save(customer.copyWith(stage: stage))),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                MobCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '跟进记录',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => unawaited(_logFollowUp()),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('记录跟进'),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        customer.note.isEmpty ? '还没有跟进记录' : customer.note,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: customer.note.isEmpty
                              ? theme.colorScheme.outline
                              : null,
                          height: 1.5,
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
                        '档案信息',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '创建：${_format(customer.createdAt)}\n'
                        '更新：${_format(customer.updatedAt)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _fieldTile(
    ThemeData theme, {
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Mob.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 64,
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
              size: 16,
              color: theme.colorScheme.outlineVariant,
            ),
          ],
        ),
      ),
    );
  }

  String _format(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
