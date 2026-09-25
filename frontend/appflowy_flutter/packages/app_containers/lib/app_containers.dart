/// 容器（分类）模型 —— 二次开发基础设施。
///
/// 背景：上游 AppFlowy 没有"文件夹"概念，整棵页面树就是"可无限嵌套的集合"。
/// 我们的做法（见 doc/现有模块复用与扩展分析.md）：
/// - **容器 = 顶层页面**，用 `view.extra` 里的自定义标记区分（`af_container` / `af_module`）；
/// - 记录 = 容器下的子页面（保留块编辑、双链、搜索、回收站）；
/// - 预置 4 个分类容器：**笔记 / 日历 / CRM / AI 交流**（与上游默认的 Getting started 页面同类，
///   只是多写了标记，没有任何新数据模型）；
/// - 「闪念 / 工作记录 / 生活日记」是**笔记容器下的普通子页面**（见 [kDefaultSubPages]），可继续无限嵌套；
/// - 后续可在设置页新建更多容器。
///
/// 本包只包含模型与契约（不依赖内核），具体实现由 App 侧适配器注入。
library app_containers;

/// 模块标识（用于容器标记与路由）。
class ContainerModule {
  const ContainerModule._();

  static const String flashNote = 'flash_note';
  static const String note = 'note';
  static const String diary = 'diary';
  static const String crm = 'crm';
  static const String ai = 'ai';

  /// 用户自定义容器（设置页新建）统一用这个模块标识。
  static const String custom = 'custom';
}

/// 容器在 view.extra 中使用的键（自有命名空间，避免与上游键冲突）。
class ContainerExtKeys {
  const ContainerExtKeys._();

  /// `true` 表示这是一个容器页面。
  static const String isContainerKey = 'af_container';

  /// 容器归属的模块标识，取值见 [ContainerModule]。
  static const String moduleKey = 'af_module';

  /// 容器图标（emoji）。
  static const String iconKey = 'af_icon';

  /// 容器创建时间（毫秒时间戳）。
  static const String createdAtKey = 'af_created_at';
}

/// 预设容器定义。
class ContainerSpec {
  const ContainerSpec({
    required this.module,
    required this.name,
    required this.icon,
  });

  final String module;
  final String name;
  final String icon;
}

/// 默认容器清单（与产品确认一致：闪念 / 笔记 / CRM / AI）。
///
/// 说明：日记条目默认落在「笔记」容器下；若之后希望日记独立成容器，
/// 在此清单加一行即可（历史数据不受影响，只影响新建落点）。
const List<ContainerSpec> kDefaultContainers = [
  ContainerSpec(
    module: ContainerModule.note,
    name: '笔记',
    icon: '📝',
  ),
  ContainerSpec(
    module: ContainerModule.diary,
    name: '日历',
    icon: '📅',
  ),
  ContainerSpec(
    module: ContainerModule.crm,
    name: 'CRM',
    icon: '👥',
  ),
  ContainerSpec(
    module: ContainerModule.ai,
    name: 'AI 交流',
    icon: '🤖',
  ),
];

/// 默认子页面：容器 → 该容器下自动存在的**普通页面**（沿用上游页面模型，可再无限嵌套）。
const Map<String, List<({String name, String icon})>> kDefaultSubPages = {
  ContainerModule.note: [
    (name: '闪念', icon: '⚡️'),
    (name: '工作记录', icon: '🗂'),
    (name: '生活日记', icon: '📔'),
  ],
};

/// 日记文档（标题=日期）默认挂在「笔记 → 生活日记」下。
const String kDiaryParentContainerModule = ContainerModule.note;
const String kDiaryParentPageName = '生活日记';

/// 运行期的容器（= 一个带标记的顶层页面）。
class ModuleContainer {
  const ModuleContainer({
    required this.viewId,
    required this.name,
    required this.module,
    this.icon,
  });

  /// 对应的内核 view id。
  final String viewId;
  final String name;
  final String module;
  final String? icon;

  bool get isCustom => module == ContainerModule.custom;
}

/// 容器仓储契约（实现见 App 侧适配器 `ContainerRepositoryImpl`）。
abstract interface class ContainerRepository {
  /// 列出当前工作空间的全部容器（含用户在设置页新建的）。
  Future<List<ModuleContainer>> listContainers();

  /// 确保某个预设容器存在，返回它（幂等）。
  Future<ModuleContainer> ensureContainer(ContainerSpec spec);

  /// 新建自定义容器（设置页使用）。
  Future<ModuleContainer> createContainer({
    required String name,
    String icon = '📁',
  });
}
