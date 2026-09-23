import 'dart:async';

import 'package:app_containers/app_containers.dart';
import 'package:app_flash_note/app_flash_note.dart';
import 'package:appflowy/extensions/adapters/container_repository_impl.dart';
import 'package:appflowy/extensions/flash_note_entry.dart';
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
                _ComingSoonView(
                  icon: Icons.calendar_month_outlined,
                  title: '日历',
                  description: '时间日记模块开发中\n这里将展示月历与每日日记',
                  onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                _ContainerRecordsView(
                  container: _containerOf(ContainerModule.crm),
                  repository: _repository,
                  title: 'CRM',
                  showDrawerButton: true,
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
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('新建${container.name}记录'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '标题（可留空）'),
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
    if (name == null) {
      return;
    }
    final result = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: container.viewId,
      name: name.isEmpty ? '未命名页面' : name,
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

class _ComingSoonView extends StatelessWidget {
  const _ComingSoonView({
    required this.icon,
    required this.title,
    required this.description,
    this.onOpenDrawer,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onOpenDrawer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: onOpenDrawer,
        ),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                height: 1.6,
              ),
            ),
          ],
        ),
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
    required this.containerName,
    this.onOpenDrawer,
  });

  final String workspaceId;
  final Int64 userId;
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
          IconButton(
            tooltip: '闪念速记',
            icon: const Icon(Icons.bolt),
            onPressed: _capture,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _capture,
        icon: const Icon(Icons.add),
        label: const Text('闪念'),
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
