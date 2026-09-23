/// 二次开发开关：本地优先模式（Local-first）。
///
/// 对应产品蓝图《整体架构设计规范》中的"放弃 AppFlowy Cloud、全本地优先 + WebDAV 快照同步"，
/// 以及《项目开发目标与产品蓝图》中的"数据本地优先：隐私自主可控"。
///
/// 该开关为 true 时：
/// 1. 应用启动即进入本地（匿名）模式，跳过 AppFlowy Cloud 登录/注册，直接进入本地工作空间；
/// 2. 认证类型固定为 [AuthenticatorType.local]，不初始 AppFlowy Cloud 相关服务，不发起云同步；
/// 3. 与云相关的设置入口（云设置/账号登录/协作成员/订阅）不再展示。
///
/// 说明：这里只改前端适配层，不触碰 `frontend/rust-lib` 内核；
/// 后续接入自研 WebDAV 同步时保持该开关为 true。
const bool kLocalFirstMode = true;
