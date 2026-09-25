/// 通用 CRM 实体模型（线索 / 客户 / 联系人 / 项目 / 合同 / 收款）。
///
/// 设计取向（"不求大而全，但要能扩展"）：
/// - 所有实体共用一张表 + 一套模型：核心字段是**固定列**（便于筛选/排序），
///   额外字段放 `extra`（JSON），字段定义放 `crm_field_defs` —— 想加字段不用改表结构；
/// - 实体之间用 id 关联：`customerId / contactId / projectId / leadId`，
///   于是"客户 ↔ 联系人 ↔ 线索 ↔ 项目 ↔ 合同 ↔ 收款"是一条链，而不是六张孤岛表。
class CrmEntityType {
  const CrmEntityType._();

  static const String lead = 'lead';
  static const String customer = 'customer';
  static const String contact = 'contact';
  static const String project = 'project';
  static const String contract = 'contract';
  static const String receivable = 'receivable';

  /// 全部类型（顺序即 CRM 标签页顺序）。
  static const List<String> all = [
    lead,
    customer,
    contact,
    project,
    contract,
    receivable,
  ];

  static String label(String type) {
    switch (type) {
      case lead:
        return '线索';
      case customer:
        return '客户';
      case contact:
        return '联系人';
      case project:
        return '项目';
      case contract:
        return '合同';
      case receivable:
        return '收款';
      default:
        return type;
    }
  }

  /// 各类型的阶段（项目阶段就是"线索转项目之后"要推进的那条流水线）。
  static List<String> stages(String type) {
    switch (type) {
      case lead:
        return const ['新线索', '已联系', '已确认', '已转项目', '已丢弃'];
      case project:
        return const ['需求调研', '方案编制', '报价', '投标', '商务谈判', '已成交', '已流失'];
      case contract:
        return const ['草稿', '已签署', '履行中', '已完成', '已终止'];
      case receivable:
        return const ['未收', '部分收款', '已收齐', '逾期'];
      default:
        return const [];
    }
  }
}

/// 一条 CRM 实体记录。
class CrmEntity {
  const CrmEntity({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle = '',
    this.stage = '',
    this.amount = 0,
    this.owner = '',
    this.phone = '',
    this.note = '',
    this.eventTime,
    this.customerId = '',
    this.contactId = '',
    this.projectId = '',
    this.leadId = '',
    this.contractId = '',
    this.extra = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// [CrmEntityType] 之一。
  final String type;

  /// 标题：线索名 / 客户名 / 联系人姓名 / 项目名 / 合同名 / 收款单标题。
  final String title;

  /// 副标题：公司、岗位、客户名等一行摘要。
  final String subtitle;

  /// 阶段（无阶段类型为空）。
  final String stage;

  /// 金额（项目/合同/收款用；单位元）。
  final double amount;
  final String owner;
  final String phone;
  final String note;

  /// 关键时间：合同签署日 / 收款到期日 / 项目预计成交日等（用于与日历联动）。
  final DateTime? eventTime;

  final String customerId;
  final String contactId;
  final String projectId;
  final String leadId;

  /// 收款单指向的合同（合同→项目→客户 由此串起来）。
  final String contractId;

  /// 自定义扩展字段（存放在 `crm_field_defs` 里定义的 key）。
  final Map<String, String> extra;

  final DateTime createdAt;
  final DateTime updatedAt;

  CrmEntity copyWith({
    String? title,
    String? subtitle,
    String? stage,
    double? amount,
    String? owner,
    String? phone,
    String? note,
    DateTime? eventTime,
    String? customerId,
    String? contactId,
    String? projectId,
    String? leadId,
    String? contractId,
    Map<String, String>? extra,
    DateTime? updatedAt,
  }) {
    return CrmEntity(
      id: id,
      type: type,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      stage: stage ?? this.stage,
      amount: amount ?? this.amount,
      owner: owner ?? this.owner,
      phone: phone ?? this.phone,
      note: note ?? this.note,
      eventTime: eventTime ?? this.eventTime,
      customerId: customerId ?? this.customerId,
      contactId: contactId ?? this.contactId,
      projectId: projectId ?? this.projectId,
      leadId: leadId ?? this.leadId,
      contractId: contractId ?? this.contractId,
      extra: extra ?? this.extra,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// CRM 跟踪记录（电话/拜访/会议/微信/备注…）：**带时间**，会同步进统一时间轴。
class CrmEvent {
  const CrmEvent({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.content,
    required this.eventTime,
    this.kind = '备注',
    this.linkedViewId = '',
    required this.createdAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String kind;
  final String content;
  final DateTime eventTime;

  /// 关联的内核记录页（把这次跟进"落成一篇记录"时填）。
  final String linkedViewId;
  final DateTime createdAt;

  static const List<String> kinds = ['电话', '拜访', '会议', '微信', '邮件', '备注'];
}

/// 自定义字段定义（扩展字段的"表结构"）。
class CrmFieldDef {
  const CrmFieldDef({
    required this.entityType,
    required this.key,
    required this.label,
    this.type = 'text',
    this.options = const [],
    this.sortOrder = 0,
  });

  final String entityType;
  final String key;
  final String label;

  /// text / number / date / select / checkbox
  final String type;
  final List<String> options;
  final int sortOrder;
}
