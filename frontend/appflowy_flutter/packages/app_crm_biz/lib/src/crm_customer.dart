/// CRM 客户档案（业务数据，存独立 Sqlite）。
class CrmCustomer {
  const CrmCustomer({
    required this.id,
    required this.name,
    this.company = '',
    this.stage = '',
    this.owner = '',
    this.phone = '',
    this.note = '',
    required this.createdAt,
    required this.updatedAt,
    this.linkedDocumentIds = const [],
  });

  final String id;
  final String name;
  final String company;

  /// 销售阶段：线索 / 接触 / 方案 / 投标 / 成交 / 流失。
  final String stage;
  final String owner;
  final String phone;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 关联的内核文档（方案、会议记录）view id。
  final List<String> linkedDocumentIds;

  CrmCustomer copyWith({
    String? name,
    String? company,
    String? stage,
    String? owner,
    String? phone,
    String? note,
    DateTime? updatedAt,
  }) {
    return CrmCustomer(
      id: id,
      name: name ?? this.name,
      company: company ?? this.company,
      stage: stage ?? this.stage,
      owner: owner ?? this.owner,
      phone: phone ?? this.phone,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      linkedDocumentIds: linkedDocumentIds,
    );
  }
}
