import 'dart:async';

import 'package:app_containers/app_containers.dart';
// sqlite3 也导出 Row，与 Flutter 的 Row 组件同名，这里隐藏掉
import 'package:app_biz_store/app_biz_store.dart' hide Row;
import 'package:app_crm_biz/app_crm_biz.dart';
import 'package:app_diary_time/app_diary_time.dart';
import 'package:app_flash_note/app_flash_note.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/extensions/adapters/container_repository_impl.dart';
import 'package:appflowy/extensions/flash_note_entry.dart';
import 'package:appflowy/extensions/diary_entry.dart';
import 'package:appflowy/mobile/application/mobile_router.dart';
import 'package:appflowy/mobile/presentation/home/mobile_home_setting_page.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';

/// 本地优先模式的移动端首页（抽屉 + 五项底部导航）。
///
/// 设计（与产品确认）：
/// - 主区是"内容"，不再把页面树当首页：底部导航 `首页 / 日历 / CRM / AI / 设置`；
/// - 抽屉放"分类与入口"：容器列表（闪念/笔记/CRM/AI + 自定义）、最近/收藏/回收站、通知、设置；
/// - 首页 = 当前容器的记录视图；CRM / AI 标签直接展示各自容器内容；
/// - 新建记录必然落到当前容器下（容器 = 顶层页面，记录 = 子页面）。
class LocalHomeShell extends StatefulWidget {
  const LocalHomeShell({
    super.key,
    required this.userProfile,
    required this.workspaceId,
  });

  final UserProfilePB userProfile;
  final String workspaceId;

  @override
  State<LocalHomeShell> createState() => _LocalHomeShellState();
}

class _LocalHomeShellState extends State<LocalHomeShell> {
  late final ContainerRepositoryImpl _repository = ContainerRepositoryImpl(
    workspaceId: widget.workspaceId,
    userId: widget.userProfile.id,
  );

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  List<ModuleContainer> _containers = const [];
  bool _loading = true;
  int _tabIndex = 0;

  /// 首页标签当前展示的容器（默认「闪念」）。
  ModuleContainer? _homeContainer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      // 先确保预设容器存在，再拉取全部容器（含用户在设置页/抽屉里新建的自定义容器）
      await _repository.ensureDefaultContainers();
      final containers = await _repository.listContainers();
      if (!mounted) {
        return;
      }
      setState(() {
        _containers = containers;
        _homeContainer = containers.firstWhere(
          (c) => c.module == ContainerModule.flashNote,
          orElse: () => containers.first,
        );
        _loading = false;
      });
    } catch (e) {
      Log.error('[本地首页] 容器加载失败：$e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  ModuleContainer? _containerOf(String module) {
    for (final container in _containers) {
      if (container.module == module) {
        return container;
      }
    }
    return null;
  }

  void _selectContainer(ModuleContainer container) {
    setState(() {
      _homeContainer = container;
      _tabIndex = 0;
    });
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : IndexedStack(
              index: _tabIndex,
              children: [
                // 闪念容器：直接渲染"闪念记录"（业务库），无需另一套收件箱 UI
                if (_homeContainer?.module == ContainerModule.flashNote)
                  _FlashNoteRecordsView(
                    key: ValueKey('flash_${_homeContainer?.viewId}'),
                    workspaceId: widget.workspaceId,
                    userId: widget.userProfile.id,
                    containerViewId: _homeContainer?.viewId ?? '',
                    containerName: _homeContainer?.name ?? '闪念',
                    onOpenDrawer: () =>
                        _scaffoldKey.currentState?.openDrawer(),
                  )
                else
                  _ContainerRecordsView(
                    key: ValueKey('home_${_homeContainer?.viewId}'),
                    container: _homeContainer,
                    repository: _repository,
                    title: _homeContainer?.name ?? '首页',
                    showDrawerButton: true,
                    onOpenDrawer: () =>
                        _scaffoldKey.currentState?.openDrawer(),
                    onSwitchContainer: _containers.length > 1
                        ? () => _scaffoldKey.currentState?.openDrawer()
                        : null,
                  ),
                _CalendarView(
                  workspaceId: widget.workspaceId,
                  userId: widget.userProfile.id,
                  onOpenDrawer: () =>
                      _scaffoldKey.currentState?.openDrawer(),
                ),
                _CrmView(
                  onOpenDrawer: () =>
                      _scaffoldKey.currentState?.openDrawer(),
                ),
                _ContainerRecordsView(
                  container: _containerOf(ContainerModule.ai),
                  repository: _repository,
                  title: 'AI',
                  showDrawerButton: true,
                  onOpenDrawer: () =>
                      _scaffoldKey.currentState?.openDrawer(),
                ),
                _buildSettingsTab(context),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '日历',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'CRM',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 抽屉

  Widget _buildDrawer(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    child: Text(
                      widget.userProfile.name.isEmpty
                          ? 'A'
                          : widget.userProfile.name.characters.first,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.userProfile.name.isEmpty
                          ? '本地用户'
                          : widget.userProfile.name,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                '容器',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            for (final container in _containers)
              ListTile(
                dense: true,
                leading: Text(
                  container.icon ?? '📁',
                  style: const TextStyle(fontSize: 18),
                ),
                title: Text(container.name),
                selected: container.viewId == _homeContainer?.viewId,
                onTap: () => _selectContainer(container),
              ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.add),
              title: const Text('新建容器'),
              onTap: () {
                Navigator.of(context).maybePop();
                unawaited(_createContainerFlow(context));
              },
            ),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('其他'),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.notifications_none),
              title: const Text('通知'),
              onTap: () {
                Navigator.of(context).maybePop();
                setState(() => _tabIndex = 4);
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              onTap: () {
                Navigator.of(context).maybePop();
                setState(() => _tabIndex = 4);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createContainerFlow(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建容器'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '容器名称，例如 灵感收藏'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) {
      return;
    }
    try {
      await _repository.createContainer(name: name);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(this.context)
            .showSnackBar(SnackBar(content: Text('创建失败：$e')));
      }
    }
  }

  // ---------------------------------------------------------------- 设置标签

  Widget _buildSettingsTab(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('容器管理'),
            subtitle: Text('当前 ${_containers.length} 个容器'),
            onTap: () => unawaited(_createContainerFlow(context)),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('全部设置'),
            subtitle: const Text('外观 / 语言 / 数据 / 关于'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const MobileHomeSettingPage(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 日历标签页：极简月历（iOS18 风格）+ 每日日记 + 生活元数据。
///
/// - 每天一篇内核文档（标题=日期），正文用内核编辑器写；
/// - 心情/天气/位置存独立业务库，月历上以小色点标记；
/// - 点某天＝打开（必要时创建）当天日记。
class _CalendarView extends StatefulWidget {
  const _CalendarView({
    required this.workspaceId,
    required this.userId,
    this.onOpenDrawer,
  });

  final String workspaceId;
  final Int64 userId;
  final VoidCallback? onOpenDrawer;

  @override
  State<_CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<_CalendarView> {
  DiaryService? _service;
  bool _loading = true;
  late DateTime _month;
  late DateTime _selected;
  Map<String, DiaryEntry> _entries = {};

  @override
  void initState() {
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final service = await createDiaryService(
        workspaceId: widget.workspaceId,
        userId: widget.userId,
      );
      if (!mounted) {
        return;
      }
      setState(() => _service = service);
      await _reload();
    } catch (e) {
      Log.error('[日记] 初始化失败：$e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _reload() async {
    final service = _service;
    if (service == null) {
      return;
    }
    final entries = await service.entriesOfMonth(_month);
    if (!mounted) {
      return;
    }
    setState(() {
      _entries = {for (final entry in entries) entry.dateKey: entry};
      _loading = false;
    });
  }

  Future<void> _openDiary(DateTime date) async {
    final service = _service;
    if (service == null) {
      return;
    }
    try {
      final entry = await service.openOrCreate(date);
      await _reload();
      final documentId = entry.documentId;
      if (documentId != null && mounted) {
        await openDocumentByViewId(context, documentId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打开日记失败：$e')));
      }
    }
  }

  Future<void> _pickMoodOrWeather({required bool mood}) async {
    final service = _service;
    if (service == null) {
      return;
    }
    final options = mood ? kDiaryMoods : kDiaryWeathers;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mood ? '今天心情' : '今天天气',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final option in options)
                  ActionChip(
                    label: Text(
                      '${option.$1} ${option.$2}',
                      style: const TextStyle(fontSize: 15),
                    ),
                    onPressed: () =>
                        Navigator.of(sheetContext).pop(option.$1),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (selected == null || selected.isEmpty) {
      return;
    }
    if (mood) {
      await service.setMood(_selected, selected);
    } else {
      await service.setWeather(_selected, selected);
    }
    await _reload();
  }

  Future<void> _editLocation() async {
    final service = _service;
    if (service == null) {
      return;
    }
    final controller = TextEditingController(
      text: _entries[DiaryEntry.keyOf(_selected)]?.location ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('地点'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如 济南 · 客户现场'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null) {
      return;
    }
    await service.setLocation(_selected, value);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedEntry = _entries[DiaryEntry.keyOf(_selected)];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: widget.onOpenDrawer,
        ),
        title: const Text('日历'),
        actions: [
          TextButton(
            onPressed: () {
              final now = DateTime.now();
              setState(() {
                _month = DateTime(now.year, now.month);
                _selected = DateTime(now.year, now.month, now.day);
              });
              unawaited(_reload());
            },
            child: const Text('今天'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                // 月份大标题（iOS18 风格：大号、留白）
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_month.year}年${_month.month}月',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () {
                        setState(() {
                          _month = DateTime(_month.year, _month.month - 1);
                        });
                        unawaited(_reload());
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () {
                        setState(() {
                          _month = DateTime(_month.year, _month.month + 1);
                        });
                        unawaited(_reload());
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildWeekHeader(theme),
                const SizedBox(height: 4),
                _buildMonthGrid(theme),
                const SizedBox(height: 20),
                _buildSelectedDayCard(theme, selectedEntry),
              ],
            ),
    );
  }

  Widget _buildWeekHeader(ThemeData theme) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: [
        for (final label in labels)
          Expanded(
            child: Center(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMonthGrid(ThemeData theme) {
    final firstDay = DateTime(_month.year, _month.month);
    // 周一为一周起点
    final leading = (firstDay.weekday - DateTime.monday) % 7;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final today = DateTime.now();
    final cells = <Widget>[];

    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final key = DiaryEntry.keyOf(date);
      final entry = _entries[key];
      final isSelected = DiaryEntry.keyOf(_selected) == key;
      final isToday = DiaryEntry.keyOf(today) == key;

      cells.add(
        GestureDetector(
          onTap: () => setState(() => _selected = date),
          onDoubleTap: () => unawaited(_openDiary(date)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : (isToday
                            ? theme.colorScheme.primaryContainer
                            : Colors.transparent),
                  ),
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 15,
                      color: isSelected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: entry == null
                        ? Colors.transparent
                        : _moodColor(entry.mood, theme),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.82,
      children: cells,
    );
  }

  Widget _buildSelectedDayCard(ThemeData theme, DiaryEntry? entry) {
    return _RecordCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DiaryEntry.keyOf(_selected),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: Text(
                  entry == null || entry.mood.isEmpty
                      ? '😊 记心情'
                      : entry.mood,
                  style: const TextStyle(fontSize: 15),
                ),
                onPressed: () => _pickMoodOrWeather(mood: true),
              ),
              ActionChip(
                label: Text(
                  entry == null || entry.weather.isEmpty
                      ? '⛅ 记天气'
                      : entry.weather,
                  style: const TextStyle(fontSize: 15),
                ),
                onPressed: () => _pickMoodOrWeather(mood: false),
              ),
              ActionChip(
                avatar: const Icon(Icons.place_outlined, size: 16),
                label: Text(
                  entry == null || entry.location.isEmpty
                      ? '地点'
                      : entry.location,
                  style: const TextStyle(fontSize: 15),
                ),
                onPressed: _editLocation,
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: () => _openDiary(_selected),
              child: Text(
                (entry?.hasDocument ?? false) ? '打开当天日记' : '写今天的日记',
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 心情 → 月历色点颜色（低饱和，符合 iOS 风格）。
  Color _moodColor(String mood, ThemeData theme) {
    switch (mood) {
      case '😄':
        return const Color(0xFF34C759);
      case '🙂':
        return const Color(0xFF30B0C7);
      case '😐':
        return const Color(0xFF8E8E93);
      case '😔':
        return const Color(0xFF5E5CE6);
      case '😡':
        return const Color(0xFFFF3B30);
      default:
        return theme.colorScheme.primary.withValues(alpha: 0.7);
    }
  }
}

/// 容器内容视图：展示某个容器下的所有记录（子页面）。
class _ContainerRecordsView extends StatefulWidget {
  const _ContainerRecordsView({
    super.key,
    required this.container,
    required this.repository,
    required this.title,
    this.showDrawerButton = false,
    this.onOpenDrawer,
    this.onSwitchContainer,
  });

  final ModuleContainer? container;
  final ContainerRepositoryImpl repository;
  final String title;
  final bool showDrawerButton;

  /// 打开外层（LocalHomeShell）的抽屉。
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onSwitchContainer;

  @override
  State<_ContainerRecordsView> createState() => _ContainerRecordsViewState();
}

class _ContainerRecordsViewState extends State<_ContainerRecordsView> {
  List<ViewPB> _records = const [];
  bool _loading = true;

  /// 记录视图形态：列表 / 网格 / 时间线（iOS18 风格轻量切换）。
  _RecordViewMode _mode = _RecordViewMode.list;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant _ContainerRecordsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.container?.viewId != widget.container?.viewId) {
      unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    final container = widget.container;
    if (container == null) {
      setState(() {
        _records = const [];
        _loading = false;
      });
      return;
    }
    final result = await ViewBackendService.getAllViews();
    final views = result.toNullable()?.items ?? const <ViewPB>[];
    final records = views
        .where((view) => view.parentViewId == container.viewId)
        .toList()
      ..sort((a, b) => _sortKey(b).compareTo(_sortKey(a)));
    if (!mounted) {
      return;
    }
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  Future<void> _createRecord() async {
    final container = widget.container;
    if (container == null) {
      return;
    }
    // 直接新建一篇普通笔记并进入编辑器（与上游「新建页面」一致：默认标题为空，
    // 由内核显示为"未命名页面"），不再弹标题输入窗口。
    final result = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: container.viewId,
      name: '',
    );
    final view = result.toNullable();
    if (view == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('创建失败')));
      }
      return;
    }
    await _reload();
    if (mounted) {
      await context.pushView(view);
    }
  }

  Future<void> _open(ViewPB view) async {
    await context.pushView(view);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final container = widget.container;
    return Scaffold(
      appBar: AppBar(
        leading: widget.showDrawerButton
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: widget.onOpenDrawer,
              )
            : null,
        title: widget.onSwitchContainer == null
            ? Text(widget.title)
            : InkWell(
                onTap: widget.onSwitchContainer,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.title),
                    const Icon(Icons.expand_more, size: 20),
                  ],
                ),
              ),
        actions: [
          PopupMenuButton<_RecordViewMode>(
            tooltip: '视图样式',
            icon: Icon(
              switch (_mode) {
                _RecordViewMode.list => Icons.view_list_outlined,
                _RecordViewMode.grid => Icons.grid_view_outlined,
                _RecordViewMode.timeline => Icons.timeline_outlined,
              },
            ),
            onSelected: (mode) => setState(() => _mode = mode),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _RecordViewMode.list,
                child: Text('列表'),
              ),
              PopupMenuItem(
                value: _RecordViewMode.grid,
                child: Text('网格'),
              ),
              PopupMenuItem(
                value: _RecordViewMode.timeline,
                child: Text('时间线'),
              ),
            ],
          ),
          if (container != null)
            IconButton(
              tooltip: '新建',
              icon: const Icon(Icons.add),
              onPressed: _createRecord,
            ),
        ],
      ),
      floatingActionButton: container == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _createRecord,
              icon: const Icon(Icons.add),
              label: const Text('新建'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : RefreshIndicator(
              onRefresh: _reload,
              child: _records.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: _EmptyHint(containerName: container?.name ?? ''),
                        ),
                      ],
                    )
                  : switch (_mode) {
                      _RecordViewMode.list => _buildList(),
                      _RecordViewMode.grid => _buildGrid(),
                      _RecordViewMode.timeline => _buildTimeline(),
                    },
            ),
    );
  }

  // ------------------------------------------------------------ 列表样式

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      itemCount: _records.length,
      itemBuilder: (context, index) {
        final view = _records[index];
        return _RecordCard(
          margin: const EdgeInsets.symmetric(vertical: 4),
          onTap: () => _open(view),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titleOf(view),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatTime(view),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: Theme.of(context).colorScheme.outline,
              ),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------ 网格样式

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.35,
      ),
      itemCount: _records.length,
      itemBuilder: (context, index) {
        final view = _records[index];
        return _RecordCard(
          onTap: () => _open(view),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _titleOf(view),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatTime(view),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------- 时间线样式

  Widget _buildTimeline() {
    final theme = Theme.of(context);
    String? lastDay;
    final children = <Widget>[];
    for (final view in _records) {
      final day = _dayOf(view);
      if (day != lastDay) {
        lastDay = day;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
            child: Text(
              day,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        );
      }
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧时间轴：圆点 + 连线
              Column(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.primary.withValues(alpha: 0.8),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 44,
                    color: theme.colorScheme.outlineVariant,
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RecordCard(
                  onTap: () => _open(view),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _titleOf(view),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, height: 1.35),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _timeOfDay(view),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      children: children,
    );
  }

  String _titleOf(ViewPB view) =>
      view.name.isEmpty ? '未命名页面' : view.name;

  DateTime? _timeOf(ViewPB view) {
    final timestamp = _sortKey(view);
    if (timestamp == Int64.ZERO) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(timestamp.toInt() * 1000);
  }

  String _dayOf(ViewPB view) {
    final time = _timeOf(view);
    if (time == null) {
      return '未知时间';
    }
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }

  String _timeOfDay(ViewPB view) {
    final time = _timeOf(view);
    if (time == null) {
      return '';
    }
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}';
  }

  String _formatTime(ViewPB view) {
    final timestamp = _sortKey(view);
    if (timestamp == Int64.ZERO) {
      return '';
    }
    // 内核返回的时间戳单位是「秒」，需要换算成毫秒再格式化。
    final time = DateTime.fromMillisecondsSinceEpoch(timestamp.toInt() * 1000);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  /// 排序/展示用的时间戳：优先最后编辑时间，其次创建时间。
  Int64 _sortKey(ViewPB view) {
    return view.lastEdited == Int64.ZERO ? view.createTime : view.lastEdited;
  }
}

/// 记录视图形态。
enum _RecordViewMode { list, grid, timeline }

/// iOS18 风格的记录卡片：大圆角、低饱和表面色、无重边框。
class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.child,
    this.onTap,
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: margin,
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.containerName});

  final String containerName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            '$containerName 还没有内容\n点右下角新建，或从抽屉切换容器',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// 「闪念」容器的首页视图：直接展示闪念记录（业务库），并入捕获与整理动作。
///
/// 这样原来的独立"闪念收件箱"页不再是必需的（减少一套 UI）。
class _FlashNoteRecordsView extends StatefulWidget {
  const _FlashNoteRecordsView({
    super.key,
    required this.workspaceId,
    required this.userId,
    required this.containerViewId,
    required this.containerName,
    this.onOpenDrawer,
  });

  final String workspaceId;
  final Int64 userId;
  final String containerViewId;
  final String containerName;
  final VoidCallback? onOpenDrawer;

  @override
  State<_FlashNoteRecordsView> createState() => _FlashNoteRecordsViewState();
}

class _FlashNoteRecordsViewState extends State<_FlashNoteRecordsView> {
  FlashNoteService? _service;
  List<FlashNote> _notes = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final service = await createFlashNoteService(
        workspaceId: widget.workspaceId,
        userId: widget.userId,
      );
      if (!mounted) {
        return;
      }
      setState(() => _service = service);
      await _reload();
    } catch (e) {
      Log.error('[闪念] 初始化失败：$e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _reload() async {
    final service = _service;
    if (service == null) {
      return;
    }
    final notes = await service.inbox();
    if (!mounted) {
      return;
    }
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  Future<void> _capture() async {
    final service = _service;
    if (service == null) {
      return;
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FlashNoteCapturePage(service: service),
      ),
    );
    if (saved ?? false) {
      await _reload();
    }
  }

  /// FAB：直接新建一篇普通笔记并进入编辑器（不再弹标题/捕获窗口）。
  Future<void> _createNote() async {
    if (widget.containerViewId.isEmpty) {
      return;
    }
    final result = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: widget.containerViewId,
      name: '',
    );
    final view = result.toNullable();
    if (view == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('新建失败')));
      }
      return;
    }
    await _reload();
    if (mounted) {
      await context.pushView(view);
    }
  }

  Future<void> _open(FlashNote note) async {
    final service = _service;
    if (service == null) {
      return;
    }
    var target = note;
    if (!note.hasDocument) {
      try {
        target = await service.promoteToDocument(note);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('转入知识库失败：$e')));
        }
        return;
      }
      await _reload();
    }
    final documentId = target.documentId;
    if (documentId == null || !mounted) {
      return;
    }
    await openDocumentByViewId(context, documentId);
  }

  Future<void> _archive(FlashNote note) async {
    await _service?.archive(note);
    await _reload();
  }

  Future<void> _delete(FlashNote note) async {
    await _service?.delete(note);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: widget.onOpenDrawer,
        ),
        title: Text(widget.containerName),
        actions: [
          // 顶栏「+」= 直接新建普通笔记（与 FAB 同一动作，便于单手/自动化可达）
          IconButton(
            tooltip: '新建笔记',
            icon: const Icon(Icons.add),
            onPressed: _createNote,
          ),
          IconButton(
            tooltip: '闪念速记',
            icon: const Icon(Icons.bolt),
            onPressed: _capture,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNote,
        icon: const Icon(Icons.add),
        label: const Text('新建'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : RefreshIndicator(
              onRefresh: _reload,
              child: _notes.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: const _EmptyHint(containerName: '闪念'),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                      itemCount: _notes.length,
                      itemBuilder: (context, index) {
                        final note = _notes[index];
                        return _RecordCard(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          onTap: () => _open(note),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      note.text,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${_formatTime(note.createdAt)} · '
                                      '${note.hasDocument ? '已在知识库' : '仅记录'}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_horiz, size: 20),
                                onSelected: (value) async {
                                  switch (value) {
                                    case 'promote':
                                      await _open(note);
                                      break;
                                    case 'archive':
                                      await _archive(note);
                                      break;
                                    case 'delete':
                                      await _delete(note);
                                      break;
                                  }
                                },
                                itemBuilder: (_) => [
                                  if (!note.hasDocument)
                                    const PopupMenuItem(
                                      value: 'promote',
                                      child: Text('转入知识库'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'archive',
                                    child: Text('归档'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  String _formatTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

/// CRM 标签页：客户档案（独立业务库）+ 阶段筛选 + 快录。
///
/// v0 覆盖：客户列表（卡片）、阶段筛选、新建客户、删除；
/// 后续：跟进流水、客户 ↔ 知识库文档互链、统计漏斗。
class _CrmView extends StatefulWidget {
  const _CrmView({this.onOpenDrawer});

  final VoidCallback? onOpenDrawer;

  @override
  State<_CrmView> createState() => _CrmViewState();
}

class _CrmViewState extends State<_CrmView> {
  CrmRepository? _repository;
  List<CrmCustomer> _customers = const [];
  bool _loading = true;
  String _stageFilter = '';

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final baseDirectory = await getIt<ApplicationDataStorage>().getPath();
      final database = await BusinessDatabase.open(
        directory: baseDirectory,
        migrations: kCrmMigrations,
      );
      if (!mounted) {
        return;
      }
      setState(() => _repository = CrmRepositoryImpl(database));
      await _reload();
    } catch (e) {
      Log.error('[CRM] 初始化失败：$e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _reload() async {
    final repository = _repository;
    if (repository == null) {
      return;
    }
    final customers = await repository.listCustomers(
      stage: _stageFilter.isEmpty ? null : _stageFilter,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _customers = customers;
      _loading = false;
    });
  }

  Future<void> _createCustomer() async {
    final repository = _repository;
    if (repository == null) {
      return;
    }
    final nameController = TextEditingController();
    final companyController = TextEditingController();
    var stage = _stageFilter.isEmpty ? kCrmStages.first : _stageFilter;

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        // 保存动作：按钮与键盘"完成/回车"共用（部分机型系统手势会吞掉按钮点击）
        Future<void> submit() async {
          final name = nameController.text.trim();
          if (name.isEmpty) {
            return;
          }
          await repository.createCustomer(
            name: name,
            company: companyController.text.trim(),
            stage: stage,
          );
          if (sheetContext.mounted) {
            Navigator.of(sheetContext).pop(true);
          }
        }

        return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '新建客户',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(submit()),
                decoration: const InputDecoration(
                  labelText: '客户姓名',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: companyController,
                decoration: const InputDecoration(
                  labelText: '公司 / 单位',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in kCrmStages)
                    ChoiceChip(
                      label: Text(option),
                      selected: stage == option,
                      onSelected: (_) =>
                          setSheetState(() => stage = option),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => unawaited(submit()),
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      );
      },
    );
    if (created ?? false) {
      await _reload();
    }
  }

  Future<void> _delete(CrmCustomer customer) async {
    await _repository?.deleteCustomer(customer.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: widget.onOpenDrawer,
        ),
        title: const Text('CRM'),
        actions: [
          IconButton(
            tooltip: '新建客户',
            icon: const Icon(Icons.person_add_alt),
            onPressed: _createCustomer,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createCustomer,
        icon: const Icon(Icons.add),
        label: const Text('新建客户'),
      ),
      body: Column(
        children: [
          // 阶段筛选（iOS18 风格 chip 行）
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final option in ['', ...kCrmStages])
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 6),
                    child: ChoiceChip(
                      label: Text(option.isEmpty ? '全部' : option),
                      selected: _stageFilter == option,
                      onSelected: (_) {
                        setState(() => _stageFilter = option);
                        unawaited(_reload());
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: _customers.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.5,
                                child: const _EmptyHint(containerName: 'CRM'),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                            itemCount: _customers.length,
                            itemBuilder: (context, index) {
                              final customer = _customers[index];
                              return _RecordCard(
                                margin:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      child: Text(
                                        customer.name.isEmpty
                                            ? '?'
                                            : customer.name.characters.first,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            customer.name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            [
                                              if (customer.company.isNotEmpty)
                                                customer.company,
                                              if (customer.stage.isNotEmpty)
                                                customer.stage,
                                            ].join(' · '),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .outline,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 20,
                                      ),
                                      onPressed: () => _delete(customer),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
