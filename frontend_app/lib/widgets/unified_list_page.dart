import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../navigation/tab_scroll_registry.dart';
import 'chunked_masonry_sliver.dart';
import 'login_required.dart';

/// 加载数据的回调：返回指定分页的数据列表
typedef ItemLoader<T> = Future<List<T>> Function(int limit, int offset);

/// 搜索数据的回调：返回指定分页的搜索结果
typedef SearchLoader<T> =
    Future<List<T>> Function(String query, int limit, int offset);

/// 刷新数据的回调：返回新增数量
typedef ItemRefresher = Future<int> Function();

/// 刷新成功后的提示文案生成器（传入新增数量，返回 SnackBar 文案；返回 null 则不提示）
typedef RefreshMessageBuilder = String? Function(int count);

/// 列表项构建器：传入上下文、当前项、当前索引、全部已加载数据，以及更新回调(支持索引和 articleId)
typedef ItemWidgetBuilder<T> =
    Widget Function(
      BuildContext context,
      T item,
      int index,
      List<T> allItems,
      bool isSearchActive,
      void Function(int index, T newItem) updateItem,
      void Function(int articleId, T Function(T) updater) updateItemById,
      void Function(int articleId) removeItemById,
    );

/// 骨架卡片构建器
typedef SkeletonBuilder = Widget Function(ColorScheme colorScheme);

/// 主内容的排列方式。
enum UnifiedListLayout { list, masonry }

/// 在指定列表项前构建一个占满可用宽度的组件。
///
/// 普通列表中它会与条目纵向排列；瀑布流中它会切断网格并独占一行，
/// 适合阅读分界线等不能被限制在单列宽度内的内容。
typedef FullWidthLeadingBuilder<T> =
    Widget? Function(
      BuildContext context,
      T item,
      int index,
      List<T> allItems,
      bool isSearchActive,
    );

/// 通用分页列表页，封装了分页加载、骨架屏、空状态、下拉刷新、搜索和筛选逻辑。
/// 可以通过泛型 [T] 适配任意数据类型（文章、期刊等）。
class UnifiedListPage<T> extends StatefulWidget {
  /// AppBar 标题
  final String title;

  /// AppBar 右侧额外操作按钮（显示在内置按钮之前）
  final List<Widget>? actions;

  /// 加载数据的回调
  final ItemLoader<T> loadItems;

  /// 列表项构建器
  final ItemWidgetBuilder<T> itemBuilder;

  /// 骨架卡片构建器
  final SkeletonBuilder skeletonBuilder;

  /// 骨架卡片数量
  final int skeletonCount;

  /// 主内容排列方式。
  final UnifiedListLayout layout;

  /// 在条目前插入的全宽组件。
  final FullWidthLeadingBuilder<T>? fullWidthLeadingBuilder;

  // ── 搜索相关 ──

  /// 搜索回调（为 null 则不显示搜索按钮）
  final SearchLoader<T>? searchItems;

  /// 搜索框提示文字
  final String searchHint;

  // ── 筛选相关 ──

  /// 筛选按钮点击回调（为 null 则不显示筛选按钮）
  final VoidCallback? onFilter;

  /// 当前是否处于筛选激活状态（用于显示筛选图标的激活样式）
  final bool filterActive;

  // ── 设置 ──

  /// 设置按钮点击回调（为 null 则不显示设置按钮）
  final VoidCallback? onSettings;

  // ── 刷新相关 ──

  /// 下拉刷新回调（为 null 则禁用刷新）
  final ItemRefresher? onRefresh;

  /// 刷新完成后的额外操作（如同步状态）
  final Future<void> Function()? onPostRefresh;

  /// 刷新成功后的提示文案
  final RefreshMessageBuilder? refreshMessageBuilder;

  // ── 空状态 ──

  /// 空状态图标
  final IconData emptyIcon;

  /// 空状态标题
  final String emptyTitle;

  /// 空状态副标题
  final String emptySubtitle;

  /// 空状态按钮文案（为 null 则不显示按钮）
  final String? emptyActionLabel;

  /// 每页加载数量
  final int pageSize;

  /// 暴露 ScrollController 给外部使用（可选）
  final ScrollController? scrollController;
  final int? tabScrollIndex;
  final bool autoRefreshOnInit;
  final bool showExternalRefreshing;
  final int externalRefreshSignal;
  final VoidCallback? onUserScrollStart;
  final VoidCallback? onUserScrollEnd;

  /// 初始恢复时需要加载到的锚点。与 [matchesPreloadAnchor] 配合使用。
  final Object? preloadAnchorKey;
  final bool Function(T item)? matchesPreloadAnchor;

  const UnifiedListPage({
    super.key,
    required this.title,
    required this.loadItems,
    required this.itemBuilder,
    required this.skeletonBuilder,
    this.skeletonCount = 6,
    this.layout = UnifiedListLayout.list,
    this.fullWidthLeadingBuilder,
    this.actions,
    this.searchItems,
    this.searchHint = '搜索…',
    this.onFilter,
    this.filterActive = false,
    this.onSettings,
    this.onRefresh,
    this.onPostRefresh,
    this.refreshMessageBuilder,
    this.emptyIcon = Icons.list_alt_outlined,
    this.emptyTitle = '暂无数据',
    this.emptySubtitle = '下拉刷新以获取最新内容',
    this.emptyActionLabel,
    this.pageSize = 20,
    this.scrollController,
    this.tabScrollIndex,
    this.autoRefreshOnInit = false,
    this.showExternalRefreshing = false,
    this.externalRefreshSignal = 0,
    this.onUserScrollStart,
    this.onUserScrollEnd,
    this.preloadAnchorKey,
    this.matchesPreloadAnchor,
  });

  @override
  State<UnifiedListPage<T>> createState() => _UnifiedListPageState<T>();
}

class _UnifiedListPageState<T> extends State<UnifiedListPage<T>> {
  late final ScrollController _scrollController;
  ScrollController? _contentScrollController;
  TabScrollRegistry? _tabScrollRegistry;
  final List<T> _items = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  Future<void>? _loadMoreFuture;
  int _loadGeneration = 0;
  bool _isPreloadingAnchor = false;
  bool _lastLoadFailed = false;
  bool _isUserScrollInProgress = false;

  // ── 搜索状态 ──
  bool _isSearchMode = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController = widget.scrollController ?? ScrollController();
    if (widget.tabScrollIndex != null) {
      _tabScrollRegistry = context.read<TabScrollRegistry>();
      // The page owns the controller, but the shell can still find it by tab.
      _tabScrollRegistry!.register(widget.tabScrollIndex!, _scrollController);
    }
    unawaited(_loadThroughPreloadAnchor());
    if (widget.autoRefreshOnInit && widget.onRefresh != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_refresh());
      });
    }
  }

  @override
  void didUpdateWidget(covariant UnifiedListPage<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preloadAnchorKey != widget.preloadAnchorKey &&
        widget.preloadAnchorKey != null) {
      unawaited(_loadThroughPreloadAnchor());
    }
    if (oldWidget.externalRefreshSignal != widget.externalRefreshSignal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_reloadVisibleItems());
      });
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null &&
        !_isUserScrollInProgress) {
      _isUserScrollInProgress = true;
      if (!widget.filterActive && _searchQuery.isEmpty) {
        widget.onUserScrollStart?.call();
      }
    } else if (notification is ScrollEndNotification &&
        _isUserScrollInProgress) {
      _isUserScrollInProgress = false;
      // 搜索或筛选可能在手势中途生效；结束回调始终派发，以关闭外部
      // 可能已经打开的用户滚动写入窗口。
      widget.onUserScrollEnd?.call();
    }

    // NestedScrollView 的外层（depth 0）只负责折叠 AppBar，它很快就会
    // 到达自身末端。分页必须只响应内层文章区，否则每次滑动都会误加载
    // 一页并让瀑布流重新估算范围，表现为滚动位置循环回跳。
    if (notification.depth == 1 &&
        notification is ScrollUpdateNotification &&
        notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 300 &&
        !_isLoading &&
        _hasMore) {
      _loadMore();
    }
    return false;
  }

  // ── 搜索逻辑 ──

  void _toggleSearch() {
    setState(() {
      _isSearchMode = !_isSearchMode;
      if (!_isSearchMode) {
        _searchController.clear();
        _searchQuery = '';
        _resetAndReload();
      } else {
        // 进入搜索模式后聚焦输入框
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchFocusNode.requestFocus();
        });
      }
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (value.trim() != _searchQuery) {
        _searchQuery = value.trim();
        _resetAndReload();
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchQuery = '';
    _resetAndReload();
    _searchFocusNode.requestFocus();
  }

  void _updateItem(int index, T newItem) {
    if (index < 0 || index >= _items.length) return;
    setState(() {
      _items[index] = newItem;
    });
  }

  /// 按条件查找并更新列表项（解决快照索引过期问题）
  void _updateItemById(int articleId, T Function(T) updater) {
    final index = _items.indexWhere((item) {
      return (item as dynamic).articleId == articleId;
    });
    if (index >= 0) {
      setState(() {
        _items[index] = updater(_items[index]);
      });
    }
  }

  void _removeItemById(int articleId) {
    final index = _items.indexWhere((item) {
      return (item as dynamic).articleId == articleId;
    });
    if (index < 0) return;
    setState(() {
      _items.removeAt(index);
      if (_currentOffset > 0) _currentOffset -= 1;
    });
  }

  void _resetAndReload() {
    _invalidatePendingLoad();
    setState(() {
      _currentOffset = 0;
      _items.clear();
      _hasMore = true;
      _isLoading = false;
    });
    _loadMore();
  }

  Future<void> _reloadVisibleItems() async {
    if (!mounted) return;
    _invalidatePendingLoad();
    setState(() {
      _currentOffset = 0;
      _items.clear();
      _hasMore = true;
      _isLoading = false;
    });
    await _loadMore();
  }

  // ── 分页加载 ──

  Future<void> _loadThroughPreloadAnchor() async {
    if (_isPreloadingAnchor) return;
    _isPreloadingAnchor = true;
    final preloadGeneration = _loadGeneration;
    try {
      do {
        await _loadMore();
        if (!mounted || preloadGeneration != _loadGeneration) return;

        final anchorKey = widget.preloadAnchorKey;
        final matcher = widget.matchesPreloadAnchor;
        if (anchorKey == null ||
            matcher == null ||
            _items.any(matcher) ||
            _lastLoadFailed ||
            !_hasMore) {
          return;
        }
      } while (mounted);
    } finally {
      _isPreloadingAnchor = false;
    }
  }

  Future<void> _loadMore() {
    final activeLoad = _loadMoreFuture;
    if (activeLoad != null) return activeLoad;

    late final Future<void> load;
    final generation = _loadGeneration;
    load = _performLoadMore(generation).whenComplete(() {
      if (identical(_loadMoreFuture, load)) {
        _loadMoreFuture = null;
      }
    });
    _loadMoreFuture = load;
    return load;
  }

  Future<void> _performLoadMore(int generation) async {
    if (_isLoading || !_hasMore) return;

    _lastLoadFailed = false;
    setState(() => _isLoading = true);
    final offset = _currentOffset;
    final searchQuery = _searchQuery;
    final useSearch =
        _isSearchMode && searchQuery.isNotEmpty && widget.searchItems != null;

    try {
      final List<T> batch;
      if (useSearch) {
        batch = await widget.searchItems!(searchQuery, widget.pageSize, offset);
      } else {
        batch = await widget.loadItems(widget.pageSize, offset);
      }

      if (mounted && generation == _loadGeneration) {
        setState(() {
          _currentOffset = offset + batch.length;
          _items.addAll(batch);
          _hasMore = batch.length == widget.pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      _lastLoadFailed = true;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加载失败: $e')));
    }
  }

  void _invalidatePendingLoad() {
    _loadGeneration += 1;
    _loadMoreFuture = null;
  }

  Future<void> _refresh() async {
    if (_isRefreshing || widget.onRefresh == null) return;

    setState(() => _isRefreshing = true);

    try {
      final count = await widget.onRefresh!();

      if (widget.onPostRefresh != null) {
        await widget.onPostRefresh!();
      }

      await _reloadVisibleItems();

      if (mounted) {
        setState(() => _isRefreshing = false);
      }

      if (mounted && count > 0) {
        final message =
            widget.refreshMessageBuilder?.call(count) ?? '已更新 $count 条新数据';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRefreshing = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('刷新失败: $e')));
      }
    }
  }

  @override
  void dispose() {
    if (widget.tabScrollIndex != null) {
      _tabScrollRegistry?.unregister(widget.tabScrollIndex!, _scrollController);
      final contentController = _contentScrollController;
      if (contentController != null) {
        _tabScrollRegistry?.unregisterContent(
          widget.tabScrollIndex!,
          contentController,
        );
      }
    }
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── 构建 AppBar Actions ──

  List<Widget> _buildActions() {
    final actions = <Widget>[];

    // 额外的自定义操作
    if (widget.actions != null) {
      actions.addAll(widget.actions!);
    }

    // 筛选按钮
    if (widget.onFilter != null) {
      actions.add(
        IconButton(
          icon: Icon(
            widget.filterActive
                ? Icons.filter_list
                : Icons.filter_list_outlined,
          ),
          tooltip: '筛选',
          onPressed: widget.onFilter,
          style: widget.filterActive
              ? IconButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                )
              : null,
        ),
      );
    }

    // 搜索按钮
    if (widget.searchItems != null) {
      actions.add(
        IconButton(
          icon: Icon(
            _isSearchMode ? Icons.search_off_rounded : Icons.search_rounded,
          ),
          tooltip: _isSearchMode ? '关闭搜索' : '搜索',
          onPressed: _toggleSearch,
        ),
      );
    }

    // 设置按钮
    if (widget.onSettings != null) {
      actions.add(
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: '设置',
          onPressed: () {
            context.push("/settings");
          },
        ),
      );
    }

    actions.add(const SizedBox(width: 4));
    return actions;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: NestedScrollView(
          controller: _scrollController,
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar.large(
              title: Text(widget.title),
              actions: _buildActions(),
            ),
          ],
          body: Builder(
            builder: (bodyContext) {
              _trackContentScrollController(bodyContext);
              return Column(
                children: [
                  // ── 搜索栏 ──
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      child: _isSearchMode
                          ? KeyedSubtree(
                              key: const ValueKey('search_open'),
                              child: _buildSearchBar(colorScheme),
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('search_closed'),
                            ),
                    ),
                  ),

                  // ── 刷新进度指示条 ──
                  // 仅在主动刷新或加载更多分页时显示（初始加载由骨架屏承担）
                  if (widget.showExternalRefreshing ||
                      _isRefreshing ||
                      (_isLoading && _items.isNotEmpty))
                    LinearProgressIndicator(
                      minHeight: 3,
                      color: colorScheme.primary,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),

                  // ── 主体内容 ──
                  Expanded(child: _buildBody(colorScheme, textTheme)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _trackContentScrollController(BuildContext context) {
    final controller = PrimaryScrollController.maybeOf(context);
    final tabIndex = widget.tabScrollIndex;
    if (controller == null ||
        tabIndex == null ||
        identical(controller, _contentScrollController)) {
      return;
    }

    final previous = _contentScrollController;
    _contentScrollController = controller;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (previous != null) {
        _tabScrollRegistry?.unregisterContent(tabIndex, previous);
      }
      _tabScrollRegistry?.registerContent(tabIndex, controller);
    });
  }

  // ── 搜索栏 ──
  Widget _buildSearchBar(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SearchBar(
        controller: _searchController,
        focusNode: _searchFocusNode,
        hintText: widget.searchHint,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Icon(Icons.search, color: colorScheme.onSurfaceVariant),
        ),
        trailing: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              onPressed: _clearSearch,
            ),
        ],
        onChanged: _onSearchChanged,
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        backgroundColor: WidgetStatePropertyAll(
          colorScheme.surfaceContainerHigh,
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme, TextTheme textTheme) {
    return LoginRequired(
      showScaffold: false,
      child: _buildListContent(colorScheme, textTheme),
    );
  }

  Widget _buildListContent(ColorScheme colorScheme, TextTheme textTheme) {
    // 首次加载 → 骨架屏
    if (_items.isEmpty && (_isLoading || widget.showExternalRefreshing)) {
      return _buildSkeletonList(colorScheme);
    }

    // 搜索模式空结果
    if (_items.isEmpty &&
        !_isLoading &&
        _isSearchMode &&
        _searchQuery.isNotEmpty) {
      return _buildSearchEmpty(colorScheme, textTheme);
    }

    // 筛选激活但无结果（非搜索模式）
    if (_items.isEmpty &&
        !_isLoading &&
        !_isSearchMode &&
        widget.filterActive) {
      return _buildFilterEmpty(colorScheme, textTheme);
    }

    // 空状态
    if (_items.isEmpty && !_isLoading) {
      return _buildEmptyState(colorScheme, textTheme);
    }

    // 数据列表
    final scrollView = widget.layout == UnifiedListLayout.masonry
        ? _buildMasonryView(colorScheme)
        : _buildListView(colorScheme);

    if (widget.onRefresh != null && !_isSearchMode) {
      return RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: 0,
        child: scrollView,
      );
    }

    return scrollView;
  }

  Widget _buildListView(ColorScheme colorScheme) {
    final allItems = List<T>.unmodifiable(_items);
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 88),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colorScheme.primary,
                ),
              ),
            ),
          );
        }
        return _buildItem(
          context,
          index,
          allItems: allItems,
          includeFullWidthLeading: true,
        );
      },
    );
  }

  Widget _buildMasonryView(ColorScheme colorScheme) {
    final allItems = List<T>.unmodifiable(_items);
    final fullWidthLeading = <int, Widget>{};
    final leadingBuilder = widget.fullWidthLeadingBuilder;
    if (leadingBuilder != null) {
      for (var index = 0; index < _items.length; index++) {
        final leading = leadingBuilder(
          context,
          _items[index],
          index,
          allItems,
          _searchQuery.isNotEmpty,
        );
        if (leading != null) fullWidthLeading[index] = leading;
      }
    }

    final slivers = <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: 4)),
      ChunkedMasonrySliver(
        itemCount: _items.length,
        fullWidthLeading: fullWidthLeading,
        itemBuilder: (context, index) => _buildItem(
          context,
          index,
          allItems: allItems,
          includeFullWidthLeading: false,
        ),
      ),
    ];

    if (_hasMore) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      );
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 88)));

    return CustomScrollView(
      key: const ValueKey('unified-masonry-grid'),
      slivers: slivers,
    );
  }

  Widget _buildItem(
    BuildContext context,
    int index, {
    required List<T> allItems,
    required bool includeFullWidthLeading,
  }) {
    final item = widget.itemBuilder(
      context,
      _items[index],
      index,
      allItems,
      _searchQuery.isNotEmpty,
      _updateItem,
      _updateItemById,
      _removeItemById,
    );
    if (!includeFullWidthLeading) return item;

    final leading = widget.fullWidthLeadingBuilder?.call(
      context,
      _items[index],
      index,
      allItems,
      _searchQuery.isNotEmpty,
    );
    if (leading == null) return item;

    return Column(mainAxisSize: MainAxisSize.min, children: [leading, item]);
  }

  // ── 骨架屏 ──
  Widget _buildSkeletonList(ColorScheme colorScheme) {
    if (widget.layout == UnifiedListLayout.masonry) {
      return MasonryGridView.count(
        key: const ValueKey('unified-masonry-skeleton'),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 88),
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        itemCount: widget.skeletonCount,
        itemBuilder: (context, index) => widget.skeletonBuilder(colorScheme),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 88),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.skeletonCount,
      itemBuilder: (context, index) => widget.skeletonBuilder(colorScheme),
    );
  }

  // ── 搜索空结果 ──
  Widget _buildSearchEmpty(ColorScheme colorScheme, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: .5),
            ),
            const SizedBox(height: 16),
            Text(
              '未找到相关结果',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '尝试使用其他关键词搜索',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: .7),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: _clearSearch,
              icon: const Icon(Icons.close_rounded),
              label: const Text('清除搜索'),
            ),
          ],
        ),
      ),
    );
  }

  // ── 筛选无结果 ──
  Widget _buildFilterEmpty(ColorScheme colorScheme, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list_off_rounded,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: .5),
            ),
            const SizedBox(height: 16),
            Text(
              '当前筛选条件下无结果',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '尝试调整或清除筛选条件',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: .7),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: widget.onFilter,
              icon: const Icon(Icons.filter_list_rounded),
              label: const Text('调整筛选'),
            ),
          ],
        ),
      ),
    );
  }

  // ── 空状态 ──
  Widget _buildEmptyState(ColorScheme colorScheme, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.emptyIcon,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: .5),
            ),
            const SizedBox(height: 16),
            Text(
              widget.emptyTitle,
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.emptySubtitle,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: .7),
              ),
            ),
            if (widget.emptyActionLabel != null &&
                widget.onRefresh != null) ...[
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(widget.emptyActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
