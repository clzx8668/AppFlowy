# 本仓库二次开发约定（AppFlowy 分支）

本文件是本仓库（`E:\Dev\AppFlowy`）的长期规则，任何在本仓库内工作的会话都必须遵守。
产品蓝图与规范以 `doc/` 下 5 份中文定稿为准，优先级：`doc/整体架构设计规范.md`（宪法级）> 其余规范。

## 一、项目定位

基于 AppFlowy 开源内核二次开发，打造：安卓+Windows 双平台、iOS 级丝滑体验、国产极速闪念记录、
真块级知识库双链、时间日记记忆体系、可插拔 CRM 业务、全本地优先隐私可控、AI 可无限迭代的个人智能记忆系统。

## 二、宪法级铁律（违反即返工）

1. **内核永不改**：`frontend/rust-lib/**`（Block 模型、CRDT、操作日志、底层存储、编辑器内核、检索引擎、双向链接内核）
   不做任何业务改造，只允许整包随上游升级。
2. **源码不删除**：原版功能一律只隐藏 UI 入口，不删文件、不改底层业务逻辑。
3. **功能只新增**：所有业务能力放进独立 Flutter Package（`frontend/appflowy_flutter/packages/` 或新建独立包）：
   - `app_flash_note` 闪念速记
   - `app_diary_time` 日记 / 日历 / 生活元数据块
   - `app_crm_biz` CRM 客户业务
   - `app_webdav_sync` WebDAV 快照同步
   - `app_ai_ext` AI 扩展
4. **双库严格分离**：Core 官方 sqlite 只读（不新增表、不改字段）；CRM/业务/统计数据放独立 sqlite。
5. **自定义块只写 payload**：心情/天气/位置/倒计时/CRM 卡片等数据全部存 `block.payload`；
   图片、录音等二进制只存文件路径，不入库。
6. 页面销毁释放 Block 内存；长列表懒加载；前台编辑期间禁止 GC / 压缩 / 同步等重型任务。

## 三、平台优先级

安卓（第一主力，体验极致打磨）> Windows（第二，大屏整理与 CRM 批量管理）> iOS（可编译、不投入打磨）；
放弃 macOS / Web。

- 安卓独占：悬浮窗速记、下拉新建、相机、录音、定位、WorkManager 后台同步。
- Windows 禁用：多工作台/多工作空间、复杂分屏与面板拖拽、原生数据库/看板视图、团队与邀请 UI。
- 两端必须一致：块能力、双链与块引用、WebDAV 同步逻辑与快照格式、设计系统（配色/圆角/字体）。

## 四、本机开发环境（Windows 主机，已固定，勿随意升级）

| 组件 | 版本 / 位置 | 说明 |
| --- | --- | --- |
| Flutter | **3.27.4**，`D:\flutter\3.27.4\bin\flutter.bat` | 上游 CI 锁定版本；本机其它 Flutter（3.29/3.32/3.41）仅供别的项目使用，本项目不要用 |
| Rust | **1.85**（已装 1.85.1） | `frontend/rust-lib/rust-toolchain.toml` 自动切换 |
| cargo-make / duckscript / cargo-ndk | 0.37.18 / 已装 / 已装 | `cargo make` 任务在 `frontend/` 下执行 |
| Android SDK | `D:\AndroidSDK`（platform 36/35/34，build-tools 36） | `ANDROID_HOME` 已配置 |
| Android NDK | **24.0.8215888**（`D:\AndroidSDK\ndk\`） | 与 `android/app/build.gradle` 的 `ndkVersion` 一致；`ANDROID_NDK_HOME` 已配置 |
| JDK | **Temurin 17**（`flutter config --jdk-dir` 已固定） | AGP 8.1 / Gradle 8.1 与 JBR 21 不兼容，勿切回 21 |
| libclang | `LIBCLANG_PATH` 指向 pip 版 libclang | bindgen（rocksdb）编译必需，缺失会报 `Unable to find libclang` |
| Android Rust 交叉编译 | **WSL Ubuntu**（`wsl -d Ubuntu -u root`） | Windows 宿主无法为 Android 编译 vendored OpenSSL，详见 `doc/开发环境与构建基线.md` |

## 五、常用命令

**Windows 桌面端**（PowerShell，注意先切 Flutter 3.27.4）：

```powershell
$env:Path = "D:\flutter\3.27.4\bin;" + $env:Path
cd E:\Dev\AppFlowy\frontend
cargo make --profile development-windows-x86 appflowy-core-dev   # 编译 Rust 内核 → dart_ffi.dll
cargo make code_generation                                       # 本地化 + freezed + 图标生成
cd appflowy_flutter
flutter run -d windows                                           # 或 flutter build windows --debug
```

**Android 端**（Rust 内核在 WSL 编译，Flutter/Gradle 仍在 Windows 侧）：

```powershell
# Rust 内核（首次需先跑 doc/tools/wsl-android-env-setup.sh 装环境与 Linux 版 NDK）
wsl -d Ubuntu -u root -- bash /mnt/e/Dev/AppFlowy/doc/tools/android-rust-build.sh

# APK
$env:Path = "D:\flutter\3.27.4\bin;" + $env:Path
Remove-Item Env:PUB_HOSTED_URL -ErrorAction SilentlyContinue
cd E:\Dev\AppFlowy\frontend\appflowy_flutter
flutter build apk --debug --target-platform android-arm64
```

更细的说明（耗时、产物、参数含义）见 `doc/开发环境与构建基线.md` 第五、六节。

## 六、已知坑（踩过的）

1. **不要设置 `PUB_HOSTED_URL` 跑 `flutter pub get`**：本机用户环境变量指向 `pub.flutter-io.cn` 镜像，
   会让 pub 把 `pubspec.lock` 全量重解析并升级依赖（例如 `flutter_math_fork` 0.7.3→0.7.4），
   升级后的包与 Flutter 3.27.4 不兼容，Windows 构建会报 `RenderObjectWithLayoutCallbackMixin` 未找到。
   正确做法：`Remove-Item Env:PUB_HOSTED_URL` 后用 pub.dev 原源执行 `flutter pub get`，保持 lock 与上游一致。
2. `flutter doctor` 全绿 ≠ 能编译本项目：Flutter 版本必须 3.27.4。
3. `cargo make --profile development-android appflowy-core-dev-android` 在 Windows 上不可用（任务脚本是 bash），
   必须走 WSL。
4. `frontend/appflowy_flutter/cargokit_options.yaml` 在本版本没有任何引用（本仓库未接入 cargokit），可忽略。
5. 本地 git tag `0.13.0`~`0.14.5` 全部指向同一个提交 `5cf3a365d`，与上游真实 tag 不对应；
   仓库真实版本号是 **0.11.4**（`frontend/appflowy_flutter/pubspec.yaml` 与 `Makefile.toml` 的 `APPFLOWY_VERSION`）。
6. **JDK 必须 17**：Gradle 8.1 + AGP 8.1 与 Android Studio 的 JBR 21 不兼容，已用
   `flutter config --jdk-dir="C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot"` 固定。
7. `appflowy_backend` 模块仍引用已停服的 `jcenter()`，Gradle 靠回落到 Maven Central 兜底，
   网络抖动时报 `Could not HEAD https://repo1.maven.org/...` 属正常现象，重试即可。
8. WSL 交叉编译 Rust 需要 bindgen 的 NDK sysroot 参数（已在 `doc/tools/android-rust-build.sh` 内设置），
   且 WSL 的 cargo-ndk 固定 3.5.4（4.x 要求 rustc ≥ 1.86）。

## 七、Git 远程与提交规范

1. `origin` = 自己的 fork（`https://github.com/clzx8668/AppFlowy.git`，日常推送目标）；
   `upstream` = 官方（`https://github.com/AppFlowy-IO/AppFlowy.git`，只按需拉 Core 修复）。`main` 跟踪 `origin/main`。
2. Fork 锁定稳定版本，不跟随上游 `main` 激进更新；上游只合并 Core 关键 Bug 修复。
3. 自有业务代码全部放在独立扩展包，不污染 `frontend/appflowy_flutter/lib` 原生目录结构。
4. 提交信息遵循 `commitlint` 约定（`core.hooksPath=.githooks` 已配置；
   `commit-msg` 依赖 `.githooks/gitlint.exe`（go-gitlint 1.1.0，已安装，该文件在 .gitignore 中豁免）；
   `pre-push` 要求工作区干净）。仓库级提交身份为 `clzx8668 <clzx8668@users.noreply.github.com>`。

## 八、真机调试（荣耀 ELZ-AN10，Android 14 / arm64）

```powershell
$env:Path = "D:\AndroidSDK\platform-tools;D:\flutter\3.27.4\bin;" + $env:Path
cd E:\Dev\AppFlowy\frontend\appflowy_flutter
flutter devices                     # 设备号 A2NMVB1806003756
flutter run -d A2NMVB1806003756     # 热重载：r / R / q
```

注意：当前 AppFlowy 0.11 默认走 AppFlowy Cloud 登录，而 `appflowy.cloud` 在本网络出口被 Cloudflare
返回 403，真机启动后会卡在登录页——二次开发需先支持跳过登录、直接进入本地工作空间
（与「放弃 AppFlowy Cloud + WebDAV 快照同步」的规划一致）。
