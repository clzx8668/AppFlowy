import 'dart:convert';

import 'package:app_biz_store/app_biz_store.dart';
import 'package:nanoid/nanoid.dart';

import 'crm_entity.dart';

/// CRM 通用实体表（线索/客户/联系人/项目/合同/收款共用）。
const String kCrmEntityTable = 'crm_entities';

/// 跟踪记录表（带时间，会同步进统一时间轴）。
const String kCrmEventTable = 'crm_events';

/// 实体 ↔ 内核记录页 的关联表（CRM 内容与首页记录打通）。
const String kCrmLinkTable = 'crm_links';

/// 自定义字段定义表（扩展字段的"表结构"）。
const String kCrmFieldDefTable = 'crm_field_defs';

/// 实体之间的**多对多关系**表（客户 ↔ 联系人 等）。
///
/// 一对多/一对一不放这里，直接用实体上的外键列表达：
/// - 项目 → 客户（一对一）：`project.customer_id`
/// - 合同 → 项目（一对一）：`contract.project_id`
/// - 项目/合同 → 客户（多对一）：`customer_id`
/// - 收款 → 合同：`receivable.contract_id`
const String kCrmRelationTable = 'crm_relations';

/// 预置字段的种入标记表（只种一次，用户改名/删除后不会被重新加回来）。
const String kCrmSeedTable = 'crm_seed_state';

const List<BusinessMigration> kCrmV2Migrations = [
  BusinessMigration('crm', 2, [
    '''
    CREATE TABLE IF NOT EXISTS $kCrmEntityTable (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      title TEXT NOT NULL DEFAULT '',
      subtitle TEXT NOT NULL DEFAULT '',
      stage TEXT NOT NULL DEFAULT '',
      amount REAL NOT NULL DEFAULT 0,
      owner TEXT NOT NULL DEFAULT '',
      phone TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      event_time INTEGER,
      customer_id TEXT NOT NULL DEFAULT '',
      contact_id TEXT NOT NULL DEFAULT '',
      project_id TEXT NOT NULL DEFAULT '',
      lead_id TEXT NOT NULL DEFAULT '',
      extra TEXT NOT NULL DEFAULT '{}',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_crm_entities_type '
        'ON $kCrmEntityTable (type, updated_at DESC);',
    'CREATE INDEX IF NOT EXISTS idx_crm_entities_customer '
        'ON $kCrmEntityTable (customer_id);',
    '''
    CREATE TABLE IF NOT EXISTS $kCrmEventTable (
      id TEXT PRIMARY KEY,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      kind TEXT NOT NULL DEFAULT '备注',
      content TEXT NOT NULL DEFAULT '',
      event_time INTEGER NOT NULL,
      linked_view_id TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_crm_events_entity '
        'ON $kCrmEventTable (entity_type, entity_id, event_time DESC);',
    '''
    CREATE TABLE IF NOT EXISTS $kCrmLinkTable (
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      view_id TEXT NOT NULL,
      PRIMARY KEY (entity_type, entity_id, view_id)
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS $kCrmFieldDefTable (
      entity_type TEXT NOT NULL,
      key TEXT NOT NULL,
      label TEXT NOT NULL DEFAULT '',
      type TEXT NOT NULL DEFAULT 'text',
      options TEXT NOT NULL DEFAULT '[]',
      sort_order INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (entity_type, key)
    );
    ''',
  ]),
  // v3：多对多关系表 + 收款→合同外键（负责人字段保留但默认不展示）
  BusinessMigration('crm', 3, [
    '''
    CREATE TABLE IF NOT EXISTS $kCrmRelationTable (
      from_type TEXT NOT NULL,
      from_id TEXT NOT NULL,
      to_type TEXT NOT NULL,
      to_id TEXT NOT NULL,
      label TEXT NOT NULL DEFAULT '',
      PRIMARY KEY (from_type, from_id, to_type, to_id)
    );
    ''',
    'CREATE INDEX IF NOT EXISTS idx_crm_relations_from '
        'ON $kCrmRelationTable (from_type, from_id);',
    'CREATE INDEX IF NOT EXISTS idx_crm_relations_to '
        'ON $kCrmRelationTable (to_type, to_id);',
    'ALTER TABLE $kCrmEntityTable ADD COLUMN contract_id TEXT NOT NULL DEFAULT "";',
  ]),
  // v4：预置字段种入标记
  BusinessMigration('crm', 4, [
    '''
    CREATE TABLE IF NOT EXISTS $kCrmSeedTable (
      key TEXT PRIMARY KEY,
      seeded_at INTEGER NOT NULL
    );
    ''',
  ]),
];

/// CRM 通用仓储。
class CrmEntityRepository {
  CrmEntityRepository(this._db);

  final BusinessDatabase _db;

  // ------------------------------------------------------------ 实体 CRUD

  Future<List<CrmEntity>> list(String type) async {
    final rows = _db.raw.select(
      'SELECT * FROM $kCrmEntityTable WHERE type = ? '
      'ORDER BY updated_at DESC;',
      [type],
    );
    return rows.map(_fromRow).toList();
  }

  Future<CrmEntity?> get(String id) async {
    final rows = _db.raw.select(
      'SELECT * FROM $kCrmEntityTable WHERE id = ?;',
      [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  /// 按关联字段查（例如某个客户下的联系人 / 项目）。
  Future<List<CrmEntity>> listRelated({
    required String type,
    required String column,
    required String value,
  }) async {
    if (value.isEmpty) {
      return const [];
    }
    final rows = _db.raw.select(
      'SELECT * FROM $kCrmEntityTable WHERE type = ? AND $column = ? '
      'ORDER BY updated_at DESC;',
      [type, value],
    );
    return rows.map(_fromRow).toList();
  }

  Future<CrmEntity> create(CrmEntity entity) async {
    await upsert(entity);
    return entity;
  }

  /// 新建并自动生成 id / 时间戳。
  Future<CrmEntity> createNew({
    required String type,
    required String title,
    String subtitle = '',
    String stage = '',
    double amount = 0,
    String owner = '',
    String phone = '',
    String note = '',
    DateTime? eventTime,
    String customerId = '',
    String contactId = '',
    String projectId = '',
    String leadId = '',
    Map<String, String> extra = const {},
  }) {
    final now = DateTime.now();
    return create(
      CrmEntity(
        id: nanoid(12),
        type: type,
        title: title,
        subtitle: subtitle,
        stage: stage,
        amount: amount,
        owner: owner,
        phone: phone,
        note: note,
        eventTime: eventTime,
        customerId: customerId,
        contactId: contactId,
        projectId: projectId,
        leadId: leadId,
        extra: extra,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> upsert(CrmEntity entity) async {
    _db.raw.execute(
      'INSERT OR REPLACE INTO $kCrmEntityTable '
      '(id, type, title, subtitle, stage, amount, owner, phone, note, '
      'event_time, customer_id, contact_id, project_id, lead_id, contract_id, extra, '
      'created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
      [
        entity.id,
        entity.type,
        entity.title,
        entity.subtitle,
        entity.stage,
        entity.amount,
        entity.owner,
        entity.phone,
        entity.note,
        entity.eventTime?.millisecondsSinceEpoch,
        entity.customerId,
        entity.contactId,
        entity.projectId,
        entity.leadId,
        entity.contractId,
        jsonEncode(entity.extra),
        entity.createdAt.millisecondsSinceEpoch,
        entity.updatedAt.millisecondsSinceEpoch,
      ],
    );
  }

  Future<void> delete(String id) async {
    _db.raw.execute('DELETE FROM $kCrmEntityTable WHERE id = ?;', [id]);
    _db.raw.execute(
      'DELETE FROM $kCrmEventTable WHERE entity_id = ?;',
      [id],
    );
    _db.raw.execute('DELETE FROM $kCrmLinkTable WHERE entity_id = ?;', [id]);
  }

  // ------------------------------------------------------------ 跟踪记录

  Future<List<CrmEvent>> eventsOf(String entityId) async {
    final rows = _db.raw.select(
      'SELECT * FROM $kCrmEventTable WHERE entity_id = ? '
      'ORDER BY event_time DESC;',
      [entityId],
    );
    return rows.map(_eventFromRow).toList();
  }

  /// 某类实体**每一条各自的最近一次跟踪记录**（entityId → 最近一条事件）。
  ///
  /// 列表卡片要显示"3 天前 · 电话"这类信息，逐条查会 N+1，所以一次查出来。
  /// 没有跟踪记录的实体不会出现在返回值里。
  Future<Map<String, CrmEvent>> latestEventsOf(String entityType) async {
    final rows = _db.raw.select(
      'SELECT * FROM $kCrmEventTable WHERE entity_type = ? '
      'ORDER BY event_time DESC;',
      [entityType],
    );
    final latest = <String, CrmEvent>{};
    for (final row in rows) {
      final event = _eventFromRow(row);
      latest.putIfAbsent(event.entityId, () => event);
    }
    return latest;
  }

  Future<CrmEvent> addEvent({
    required String entityType,
    required String entityId,
    required String content,
    DateTime? eventTime,
    String kind = '备注',
    String linkedViewId = '',
  }) async {
    final now = DateTime.now();
    final event = CrmEvent(
      id: nanoid(12),
      entityType: entityType,
      entityId: entityId,
      kind: kind,
      content: content,
      eventTime: eventTime ?? now,
      linkedViewId: linkedViewId,
      createdAt: now,
    );
    _db.raw.execute(
      'INSERT OR REPLACE INTO $kCrmEventTable '
      '(id, entity_type, entity_id, kind, content, event_time, '
      'linked_view_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?);',
      [
        event.id,
        event.entityType,
        event.entityId,
        event.kind,
        event.content,
        event.eventTime.millisecondsSinceEpoch,
        event.linkedViewId,
        event.createdAt.millisecondsSinceEpoch,
      ],
    );
    return event;
  }

  Future<void> deleteEvent(String id) async {
    _db.raw.execute('DELETE FROM $kCrmEventTable WHERE id = ?;', [id]);
  }

  /// 把跟踪记录关联到一篇内核记录页（生成/选择之后回填）。
  Future<void> updateEventLinkedView({
    required String eventId,
    required String viewId,
  }) async {
    _db.raw.execute(
      'UPDATE $kCrmEventTable SET linked_view_id = ? WHERE id = ?;',
      [viewId, eventId],
    );
  }

  // ------------------------------------------------------------ 关联页面

  Future<List<String>> linksOf(String entityId) async {
    final rows = _db.raw.select(
      'SELECT view_id FROM $kCrmLinkTable WHERE entity_id = ?;',
      [entityId],
    );
    return rows.map((row) => row['view_id'] as String).toList();
  }

  Future<void> linkView({
    required String entityType,
    required String entityId,
    required String viewId,
  }) async {
    _db.raw.execute(
      'INSERT OR REPLACE INTO $kCrmLinkTable (entity_type, entity_id, view_id) '
      'VALUES (?, ?, ?);',
      [entityType, entityId, viewId],
    );
  }

  Future<void> unlinkView({
    required String entityId,
    required String viewId,
  }) async {
    _db.raw.execute(
      'DELETE FROM $kCrmLinkTable WHERE entity_id = ? AND view_id = ?;',
      [entityId, viewId],
    );
  }

  // ------------------------------------------------------------ 自定义字段

  // ------------------------------------------------------ 多对多关系
  //
  // 目前用于「客户 ↔ 联系人」：一个联系人可服务多个客户，一个客户可有多个联系人。

  /// 取某实体关联的另一类实体 id 列表。
  Future<List<String>> relationsOf({
    required String fromType,
    required String fromId,
    required String toType,
  }) async {
    final rows = _db.raw.select(
      'SELECT to_id FROM $kCrmRelationTable '
      'WHERE from_type = ? AND from_id = ? AND to_type = ?;',
      [fromType, fromId, toType],
    );
    return rows.map((row) => row['to_id'] as String).toList();
  }

  /// 双向写入关联（便于两边都能查到）。
  Future<void> linkEntities({
    required String fromType,
    required String fromId,
    required String toType,
    required String toId,
    String label = '',
  }) async {
    _db.raw.execute(
      'INSERT OR REPLACE INTO $kCrmRelationTable '
      '(from_type, from_id, to_type, to_id, label) VALUES (?, ?, ?, ?, ?);',
      [fromType, fromId, toType, toId, label],
    );
    _db.raw.execute(
      'INSERT OR REPLACE INTO $kCrmRelationTable '
      '(from_type, from_id, to_type, to_id, label) VALUES (?, ?, ?, ?, ?);',
      [toType, toId, fromType, fromId, label],
    );
  }

  Future<void> unlinkEntities({
    required String fromType,
    required String fromId,
    required String toType,
    required String toId,
  }) async {
    _db.raw.execute(
      'DELETE FROM $kCrmRelationTable WHERE '
      '((from_type = ? AND from_id = ? AND to_type = ? AND to_id = ?) OR '
      ' (from_type = ? AND from_id = ? AND to_type = ? AND to_id = ?));',
      [fromType, fromId, toType, toId, toType, toId, fromType, fromId],
    );
  }

  /// 按外键列查（例如某客户下的项目 / 合同、某项目下的合同）。
  Future<List<CrmEntity>> listByColumn({
    required String type,
    required String column,
    required String value,
  }) =>
      listRelated(type: type, column: column, value: value);

  Future<List<CrmFieldDef>> fieldDefs(String type) async {
    final rows = _db.raw.select(
      'SELECT * FROM $kCrmFieldDefTable WHERE entity_type = ? '
      'ORDER BY sort_order ASC, key ASC;',
      [type],
    );
    return rows
        .map(
          (row) => CrmFieldDef(
            entityType: row['entity_type'] as String,
            key: row['key'] as String,
            label: row['label'] as String? ?? '',
            type: row['type'] as String? ?? 'text',
            options: (jsonDecode(row['options'] as String? ?? '[]') as List)
                .whereType<String>()
                .toList(),
            sortOrder: row['sort_order'] as int? ?? 0,
          ),
        )
        .toList();
  }

  Future<void> upsertFieldDef(CrmFieldDef def) async {
    _db.raw.execute(
      'INSERT OR REPLACE INTO $kCrmFieldDefTable '
      '(entity_type, key, label, type, options, sort_order) '
      'VALUES (?, ?, ?, ?, ?, ?);',
      [
        def.entityType,
        def.key,
        def.label,
        def.type,
        jsonEncode(def.options),
        def.sortOrder,
      ],
    );
  }

  Future<void> deleteFieldDef(String type, String key) async {
    _db.raw.execute(
      'DELETE FROM $kCrmFieldDefTable WHERE entity_type = ? AND key = ?;',
      [type, key],
    );
  }

  // ------------------------------------------------------------ 映射

  /// 首次运行时把**预置字段**种入字段定义表（每类实体一次，幂等）。
  ///
  /// 用标记表保证：只种一次 —— 用户之后改名/删掉的字段不会被"复活"。
  Future<void> seedPresetFields() async {
    for (final type in CrmEntityType.all) {
      final presets = presetFieldsOf(type);
      if (presets.isEmpty) {
        continue;
      }
      final key = 'preset_fields_$type';
      final done = _db.raw.select(
        'SELECT key FROM $kCrmSeedTable WHERE key = ?;',
        [key],
      );
      if (done.isNotEmpty) {
        continue;
      }
      for (final def in presets) {
        await upsertFieldDef(def);
      }
      _db.raw.execute(
        'INSERT OR REPLACE INTO $kCrmSeedTable (key, seeded_at) VALUES (?, ?);',
        [key, DateTime.now().millisecondsSinceEpoch],
      );
    }
  }

  CrmEntity _fromRow(Row row) {
    Map<String, String> extra = const {};
    final raw = row['extra'] as String? ?? '{}';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        extra = decoded.map((k, v) => MapEntry('$k', '${v ?? ''}'));
      }
    } catch (_) {
      extra = const {};
    }
    final eventTime = row['event_time'] as int?;
    return CrmEntity(
      id: row['id'] as String,
      type: row['type'] as String,
      title: row['title'] as String? ?? '',
      subtitle: row['subtitle'] as String? ?? '',
      stage: row['stage'] as String? ?? '',
      amount: (row['amount'] as num?)?.toDouble() ?? 0,
      owner: row['owner'] as String? ?? '',
      phone: row['phone'] as String? ?? '',
      note: row['note'] as String? ?? '',
      eventTime: eventTime == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(eventTime),
      customerId: row['customer_id'] as String? ?? '',
      contactId: row['contact_id'] as String? ?? '',
      projectId: row['project_id'] as String? ?? '',
      leadId: row['lead_id'] as String? ?? '',
      contractId: row['contract_id'] as String? ?? '',
      extra: extra,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at'] as int? ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at'] as int? ?? 0,
      ),
    );
  }

  CrmEvent _eventFromRow(Row row) => CrmEvent(
        id: row['id'] as String,
        entityType: row['entity_type'] as String,
        entityId: row['entity_id'] as String,
        kind: row['kind'] as String? ?? '备注',
        content: row['content'] as String? ?? '',
        eventTime: DateTime.fromMillisecondsSinceEpoch(
          row['event_time'] as int? ?? 0,
        ),
        linkedViewId: row['linked_view_id'] as String? ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at'] as int? ?? 0,
        ),
      );
}
