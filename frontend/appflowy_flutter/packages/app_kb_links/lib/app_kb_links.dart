/// 真块知识库双链模块（v1：页面引用索引 + 反向链接）。
///
/// 蓝图定位：五大模块之三「真块知识库模块」——块引用、嵌入、双链、知识沉淀。
///
/// 现状与取舍：
/// - 上游 AppFlowy 已内建「`@` 提及页面 / 提及块」能力（inline attribute `mention`，
///   带 `page_id`，块引用时还带 `block_id`），但**没有反向链接**（grep 全仓库无 backlink）；
/// - 因此本模块只做"索引 + 呈现"：把文档里的提及解析成出链写进独立业务库，
///   再按目标页聚合出反向链接，**完全不改内核、不复制正文**；
/// - 索引按需刷新（打开文档时刷新该文档的出链），另提供全量重建入口。
library app_kb_links;

export 'src/link_repository.dart';
export 'src/link_service.dart';
export 'src/page_ref.dart';
export 'src/ref_extractor.dart';

/// 模块标识，用于日志与路由前缀。
const String kAppKbLinksPackage = 'app_kb_links';
