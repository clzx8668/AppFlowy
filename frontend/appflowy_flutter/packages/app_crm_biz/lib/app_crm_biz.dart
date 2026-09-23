/// CRM 业务模块 —— 客户档案、跟进、销售记忆沉淀。
///
/// 蓝图定位：移动端现场快速录入，Windows 端批量管理；数据**只进独立业务库**（Sqlite），
/// 不进内核 Core 库；客户与知识库文档通过 view id 关联（后续支持块引用互链）。
///
/// 复用：内核 Document 承载方案/会议记录正文（双链、搜索、回收站）；
/// 自研：客户档案表、跟进流水、阶段漏斗、统计与移动端快录 UI。
library app_crm_biz;

export 'src/crm_customer.dart';
export 'src/crm_repository.dart';

/// 模块标识，用于日志与路由前缀。
const String kAppCrmBizPackage = 'app_crm_biz';

/// 销售阶段（与客户卡筛选用）。
const List<String> kCrmStages = [
  '线索',
  '接触',
  '方案',
  '投标',
  '成交',
  '流失',
];
