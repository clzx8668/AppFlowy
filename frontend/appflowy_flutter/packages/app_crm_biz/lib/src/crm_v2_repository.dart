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
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> upsert(CrmEntity entity) async {
    _db.raw.execute(
      'INSERT OR REPLACE INTO $kCrmEntityTable '
      '(id, type, title, subtitle, stage, amount, owner, phone, note, '
      'event_time, customer_id, contact_id, project_id, lead_id, extra, '
      'created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);',
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
