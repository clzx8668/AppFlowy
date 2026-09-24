/// 二次开发：扩展包统一接入点。
///
/// 设计意图（见 `doc/现有模块复用与扩展分析.md`）：
/// - **扩展包只做 UI 与业务编排**，块/文档能力一律走内核既有 API；
/// - 本文件是 App 与扩展包之间唯一的出入口，后续所有挂载点都集中在这里，
///   保持上游源码（`lib/plugins/**`、`lib/workspace/**`）改动最小。
///
/// 骨架阶段只做登记与日志；实现阶段在此追加：
/// 1. 路由：闪念页 / 日记页 / CRM 页 / 同步与模型设置页；
/// 2. 自定义块：把扩展包里的 `BlockComponentBuilder`（心情/天气/位置/倒计时/CRM 卡片）
///    合并进 `buildBlockComponentBuilders(...)` 的结果；
/// 3. 视图插件：用 `registerPlugin(...)` 注册扩展包自有的 `PluginBuilder`；
/// 4. AI：`getIt.registerFactory<AIRepository>(() => 自有实现)` 替换上游实现；
/// 5. 入口：移动端悬浮速记/下拉新建、Windows 全局快捷键与侧边栏入口。
///
/// 另：业务数据统一走基础设施包 `app_biz_store`（独立 Sqlite，与内核 Core 库分离）。
library;

import 'package:app_ai_ext/app_ai_ext.dart';
import 'package:app_crm_biz/app_crm_biz.dart';
import 'package:app_diary_time/app_diary_time.dart';
import 'package:app_flash_note/app_flash_note.dart';
import 'package:app_kb_links/app_kb_links.dart';
import 'package:app_webdav_sync/app_webdav_sync.dart';
import 'package:appflowy_backend/log.dart';

/// 扩展包注册表。
class ExtensionRegistry {
  ExtensionRegistry._();

  /// 已接入的扩展包标识（顺序即模块在蓝图中的编号）。
  static const List<String> packages = [
    kAppFlashNotePackage, // 极速闪念
    kAppDiaryTimePackage, // 时间日记
    kAppCrmBizPackage, // CRM 业务
    kAppWebdavSyncPackage, // WebDAV 快照同步
    kAppAiExtPackage, // AI 扩展
    kAppKbLinksPackage, // 真块知识库双链（反向链接）
  ];

  static bool _registered = false;

  static bool get isRegistered => _registered;

  /// 由启动任务 `PluginLoadTask` 调用一次。
  static void registerAll() {
    if (_registered) {
      return;
    }
    _registered = true;
    Log.info('[二次开发] 扩展包已接入：${packages.join(', ')}');
  }
}
