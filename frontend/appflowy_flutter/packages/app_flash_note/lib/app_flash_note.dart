/// 闪念速记模块（骨架）
///
/// 蓝图定位：灵感快速捕获、零负担记录、先记录后整理。
///
/// 复用（内核既有能力，勿重写）：
/// - 文档创建：`ViewBackendService.createView(...)`（正文用普通 Document 承载，自动获得块能力/双链/搜索/回收站）
/// - 编辑器：`appflowy_editor`（通过文档插件渲染）
/// - 日期解析：`DateService.queryDate('明天')`（快速记录里的时间词）
///
/// 自研：
/// - 捕获入口：移动端下拉新建 / 全局悬浮速记；Windows 全局快捷键 + 速记小窗
/// - 收件箱视图（未整理的闪念）与批量整理（转日记 / 转 CRM 跟进 / 打标签）
/// - 元数据（捕获时间、来源、标签、处理状态）写入业务库，正文仍在内核
library app_flash_note;

export 'src/flash_note.dart';
export 'src/flash_note_repository.dart';
export 'src/flash_note_service.dart';
export 'src/pages/flash_note_capture_page.dart';
export 'src/pages/flash_note_inbox_page.dart';

/// 模块标识，用于日志与路由前缀。
const String kAppFlashNotePackage = 'app_flash_note';
