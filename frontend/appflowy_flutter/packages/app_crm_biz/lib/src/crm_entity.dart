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

  /// 「已收金额」：收款单的自定义字段 `received`（预置字段，可能为空）。
  double get receivedAmount =>
      double.tryParse(extra['received']?.trim() ?? '') ?? 0;

  /// 「未收金额」＝应收 − 已收（不为负）。只有收款单有意义。
  double get unpaidAmount {
    final diff = amount - receivedAmount;
    return diff > 0 ? diff : 0;
  }

  /// 客户等级字母（预置字段 `level`，如「A 重点」→ `A`）；未设置返回空串。
  String get levelLetter {
    final raw = extra['level']?.trim() ?? '';
    if (raw.isEmpty) {
      return '';
    }
    final head = raw.substring(0, 1).toUpperCase();
    return RegExp(r'[A-Z0-9]').hasMatch(head) ? head : '';
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
    this.unit = '',
    this.maxLength,
  });

  final String entityType;
  final String key;
  final String label;

  /// text / number / date / datetime / phone / email / select / checkbox
  final String type;
  final List<String> options;
  final int sortOrder;

  /// 右侧常驻单位（如 元 / % / 月），留空则不显示。
  final String unit;

  /// 字数上限（有值时输入框右侧显示 `已输入/上限`，浅色）。
  final int? maxLength;
}

/// **预置字段**：按"常见 CRM 该有的字段"给每类实体一套，安装时自动种入
/// `crm_field_defs`。全部**非必填**，字段值存在实体自己的 `extra` 里；
/// 用户可以改名/删除，也可以再往下加自己的字段（都不改数据库结构）。
///
/// 设计原则：
/// - 只放"平时真的会用"的字段（不求大而全）；
/// - 已作为核心列存在的（标题/阶段/金额/关键日期/备注/客户/项目外键）不在这里重复，
///   避免同一个信息出现两处；
/// - 能枚举的尽量做成 `select`（手机上点一下比打字快），其余是 text / number / date。
const Map<String, List<CrmFieldDef>> kCrmPresetFields = {
  CrmEntityType.lead: [
    CrmFieldDef(
      entityType: CrmEntityType.lead,
      key: 'source',
      label: '来源',
      type: 'select',
      options: ['展会', '转介绍', '网络推广', '电话咨询', '老客户', '其他'],
    ),
    CrmFieldDef(
      entityType: CrmEntityType.lead,
      key: 'intent_company',
      label: '意向单位',
      type: 'text',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.lead,
      key: 'contact_name',
      label: '对接人',
      type: 'text',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.lead,
      key: 'phone',
      label: '电话',
      type: 'phone',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.lead,
      key: 'wechat',
      label: '微信',
      type: 'text',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.lead,
      key: 'priority',
      label: '优先级',
      type: 'select',
      options: ['高', '中', '低'],
    ),
    CrmFieldDef(
      entityType: CrmEntityType.lead,
      key: 'expected_amount',
      label: '预计金额（元）',
      type: 'number',
      unit: '元',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.lead,
      key: 'expected_date',
      label: '预计成交日期',
      type: 'date',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.lead,
      key: 'region',
      label: '地区',
      type: 'text',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.lead,
      key: 'close_reason',
      label: '关闭原因',
      type: 'select',
      options: ['价格', '工期', '资质', '竞品', '无预算', '其他'],
    ),
  ],
  CrmEntityType.customer: [
    CrmFieldDef(
      entityType: CrmEntityType.customer,
      key: 'industry',
      label: '行业',
      type: 'select',
      options: ['市政', '水务', '化工', '制药', '食品', '电力', '其他'],
    ),
    CrmFieldDef(
      entityType: CrmEntityType.customer,
      key: 'level',
      label: '客户等级',
      type: 'select',
      options: ['A 重点', 'B 一般', 'C 潜在'],
    ),
    CrmFieldDef(
      entityType: CrmEntityType.customer,
      key: 'region',
      label: '地区',
      type: 'text',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.customer,
      key: 'phone',
      label: '总机/电话',
      type: 'phone',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.customer,
      key: 'address',
      label: '地址',
      type: 'text',
      maxLength: 80,
    ),
    CrmFieldDef(
      entityType: CrmEntityType.customer,
      key: 'tax_no',
      label: '纳税人识别号',
      type: 'text',
      maxLength: 20,
    ),
    CrmFieldDef(
      entityType: CrmEntityType.customer,
      key: 'invoice_info',
      label: '开票信息',
      type: 'text',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.customer,
      key: 'source',
      label: '客户来源',
      type: 'select',
      options: ['展会', '转介绍', '网络', '老客户', '其他'],
    ),
    CrmFieldDef(
      entityType: CrmEntityType.customer,
      key: 'payment_terms',
      label: '付款习惯',
      type: 'text',
    ),
  ],
  CrmEntityType.contact: [
    CrmFieldDef(
      entityType: CrmEntityType.contact,
      key: 'job_title',
      label: '职务',
      type: 'text',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.contact,
      key: 'phone',
      label: '电话',
      type: 'phone',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.contact,
      key: 'mobile',
      label: '手机',
      type: 'phone',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.contact,
      key: 'wechat',
      label: '微信',
      type: 'text',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.contact,
      key: 'email',
      label: '邮箱',
      type: 'email',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.contact,
      key: 'role',
      label: '决策角色',
      type: 'select',
      options: ['决策人', '使用人', '影响者', '采购', '财务'],
    ),
    CrmFieldDef(
      entityType: CrmEntityType.contact,
      key: 'birthday',
      label: '生日',
      type: 'date',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.contact,
      key: 'hobby',
      label: '爱好',
      type: 'text',
    ),
  ],
  CrmEntityType.project: [
    CrmFieldDef(
      entityType: CrmEntityType.project,
      key: 'region',
      label: '项目地点',
      type: 'text',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.project,
      key: 'scale',
      label: '规模/处理量',
      type: 'text',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.project,
      key: 'win_rate',
      label: '赢率（%）',
      type: 'number',
      unit: '%',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.project,
      key: 'bid_date',
      label: '投标日期',
      type: 'date',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.project,
      key: 'delivery_date',
      label: '期望交付日期',
      type: 'date',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.project,
      key: 'competitor',
      label: '竞品情况',
      type: 'text',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.project,
      key: 'strategy',
      label: '跟进策略',
      type: 'text',
    ),
  ],
  CrmEntityType.contract: [
    CrmFieldDef(
      entityType: CrmEntityType.contract,
      key: 'contract_no',
      label: '合同编号',
      type: 'text',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.contract,
      key: 'effective_date',
      label: '生效日期',
      type: 'date',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.contract,
      key: 'expire_date',
      label: '到期日期',
      type: 'date',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.contract,
      key: 'payment_terms',
      label: '付款方式',
      type: 'select',
      options: ['预付', '进度款', '到货款', '验收款', '质保金'],
    ),
    CrmFieldDef(
      entityType: CrmEntityType.contract,
      key: 'warranty',
      label: '质保期',
      type: 'text',
      unit: '月',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.contract,
      key: 'invoice_type',
      label: '发票类型',
      type: 'select',
      options: ['专票 13%', '专票 6%', '普票'],
    ),
    CrmFieldDef(
      entityType: CrmEntityType.contract,
      key: 'our_signer',
      label: '我方签约主体',
      type: 'text',
    ),
  ],
  CrmEntityType.receivable: [
    CrmFieldDef(
      entityType: CrmEntityType.receivable,
      key: 'received',
      label: '已收金额（元）',
      type: 'number',
      unit: '元',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.receivable,
      key: 'method',
      label: '收款方式',
      type: 'select',
      options: ['银行转账', '承兑', '现金', '其他'],
    ),
    CrmFieldDef(
      entityType: CrmEntityType.receivable,
      key: 'invoice_no',
      label: '发票号',
      type: 'text',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.receivable,
      key: 'invoice_date',
      label: '开票日期',
      type: 'date',
    ),
    CrmFieldDef(
      entityType: CrmEntityType.receivable,
      key: 'invoice_amount',
      label: '开票金额（元）',
      type: 'number',
      unit: '元',
    ),
  ],
};

/// 取某类实体的预置字段。
List<CrmFieldDef> presetFieldsOf(String type) => kCrmPresetFields[type] ?? const [];
