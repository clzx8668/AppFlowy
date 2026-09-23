/// CRM 业务模块（骨架）
///
/// 蓝图定位：客户档案、拜访跟进、销售记忆沉淀；移动端现场快速录入，Windows 端批量管理。
///
/// 复用：
/// - 客户拜访记录/方案正文用内核 Document 承载（享受块引用、双链、搜索），CRM 侧只保存 view id 关联
/// - 块引用能力用于"客户卡片 ↔ 方案/会议记录"互链
///
/// 自研：
/// - 独立业务库（不污染 Core 库；蓝图要求独立 Sqlite，候选方案 drift/sqlite3_flutter_libs，Android+Windows 通用）
/// - 客户档案 / 跟进流水 / 阶段漏斗 / 标签与筛选 / 统计
/// - Windows 表格视图（批量操作）、移动端现场快录
///
/// 注意：不复用上游原生 database 视图 UI（蓝图列为禁止项），仅复用其数据能力。
library app_crm_biz;

/// 模块标识，用于日志与路由前缀。
const String kAppCrmBizPackage = 'app_crm_biz';

/// 客户档案（骨架字段，后续按业务细化）。
class CrmCustomer {
  const CrmCustomer({
    required this.id,
    required this.name,
    this.company,
    this.stage,
    this.owner,
    this.tags = const [],
    this.linkedDocumentIds = const [],
  });

  final String id;
  final String name;
  final String? company;

  /// 销售阶段（线索/接触/方案/投标/成交/流失）。
  final String? stage;
  final String? owner;
  final List<String> tags;

  /// 关联的内核文档（方案、会议记录、任务）view id。
  final List<String> linkedDocumentIds;
}

/// 业务库契约：骨架阶段只定义仓储接口，实现阶段接入独立 Sqlite。
abstract interface class CrmRepository {
  Future<List<CrmCustomer>> listCustomers({String? keyword, String? stage});
  Future<void> upsertCustomer(CrmCustomer customer);
  Future<void> deleteCustomer(String id);
}
