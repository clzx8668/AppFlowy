import 'dart:async';

import 'package:app_containers/app_containers.dart';
import 'package:appflowy/extensions/adapters/container_repository_impl.dart';
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
      final containers = await _repository.ensureDefaultContainers();
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
                _ContainerRecordsView(
                  key: ValueKey('home_${_homeContainer?.viewId}'),
                  container: _homeContainer,
                  repository: _repository,
                  title: _homeContainer?.name ?? '首页',
                  showDrawerButton: true,
                  onSwitchContainer: _containers.length > 1
                      ? () => _scaffoldKey.currentState?.openDrawer()
                      : null,
                ),
                const _ComingSoonView(
                  icon: Icons.calendar_month_outlined,
                  title: '日历',
                  description: '时间日记模块开发中\n这里将展示月历与每日日记',
                ),
                _ContainerRecordsView(
                  container: _containerOf(ContainerModule.crm),
                  repository: _repository,
                  title: 'CRM',
                  showDrawerButton: true,
                ),
                _ContainerRecordsView(
                  container: _containerOf(ContainerModule.ai),
                  repository: _repository,
                  title: 'AI',
                  showDrawerButton: true,
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
    this.onSwitchContainer,
  });

  final ModuleContainer? container;
  final ContainerRepositoryImpl repository;
  final String title;
  final bool showDrawerButton;
  final VoidCallback? onSwitchContainer;

  @override
  State<_ContainerRecordsView> createState() => _ContainerRecordsViewState();
}

class _ContainerRecordsViewState extends State<_ContainerRecordsView> {
  List<ViewPB> _records = const [];
  bool _loading = true;

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
            ? Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
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
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: _records.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final view = _records[index];
                        return ListTile(
                          title: Text(
                            view.name.isEmpty ? '未命名页面' : view.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(_formatTime(view)),
                          onTap: () => _open(view),
                        );
                      },
                    ),
            ),
    );
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
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
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
