import 'package:flutter/material.dart';

/// 加载数据的回调：返回指定分页的数据列表
typedef ItemLoader<T> = Future<List<T>> Function(int limit, int offset);

/// 刷新数据的回调：返回新增数量
typedef ItemRefresher = Future<int> Function();

/// 刷新成功后的提示文案生成器（传入新增数量，返回 SnackBar 文案；返回 null 则不提示）
typedef RefreshMessageBuilder = String? Function(int count);

/// 列表项构建器：传入上下文、当前项、当前索引、全部已加载数据
typedef ItemWidgetBuilder<T> =
    Widget Function(BuildContext context, T item, int index, List<T> allItems);

/// 骨架卡片构建器
typedef SkeletonBuilder = Widget Function(ColorScheme colorScheme);

/// 通用分页列表页，封装了分页加载、骨架屏、空状态和下拉刷新逻辑。
/// 可以通过泛型 [T] 适配任意数据类型（文章、期刊等）。
class UnifiedListPage<T> extends StatefulWidget {
  /// AppBar 标题
  final String title;

  /// AppBar 右侧操作按钮
  final List<Widget>? actions;

  /// 加载数据的回调
  final ItemLoader<T> loadItems;

  /// 列表项构建器
  final ItemWidgetBuilder<T> itemBuilder;

  /// 骨架卡片构建器
  final SkeletonBuilder skeletonBuilder;

  /// 骨架卡片数量
  final int skeletonCount;

  /// 下拉刷新回调（为 null 则禁用刷新）
  final ItemRefresher? onRefresh;

  /// 刷新完成后的额外操作（如同步状态）
  final Future<void> Function()? onPostRefresh;

  /// 刷新成功后的提示文案
  final RefreshMessageBuilder? refreshMessageBuilder;

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

  const UnifiedListPage({
    super.key,
    required this.title,
    required this.loadItems,
    required this.itemBuilder,
    required this.skeletonBuilder,
    this.skeletonCount = 6,
    this.actions,
    this.onRefresh,
    this.onPostRefresh,
    this.refreshMessageBuilder,
    this.emptyIcon = Icons.list_alt_outlined,
    this.emptyTitle = '暂无数据',
    this.emptySubtitle = '下拉刷新以获取最新内容',
    this.emptyActionLabel,
    this.pageSize = 20,
  });

  @override
  State<UnifiedListPage<T>> createState() => _UnifiedListPageState<T>();
}

class _UnifiedListPageState<T> extends State<UnifiedListPage<T>> {
  final ScrollController _scrollController = ScrollController();
  final List<T> _items = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _hasMore = true;
  int _currentOffset = 0;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 300 &&
        !_isLoading &&
        _hasMore) {
      _loadMore();
    }
    return false;
  }

  Future<void> _loadMore() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final batch = await widget.loadItems(widget.pageSize, _currentOffset);

      if (mounted) {
        setState(() {
          _currentOffset += batch.length;
          _items.addAll(batch);
          _hasMore = batch.length == widget.pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载失败: $e')));
      }
    }
  }

  Future<void> _refresh() async {
    if (_isRefreshing || widget.onRefresh == null) return;

    setState(() => _isRefreshing = true);

    try {
      final count = await widget.onRefresh!();

      setState(() {
        _currentOffset = 0;
        _items.clear();
        _hasMore = true;
        _isRefreshing = false;
      });

      await _loadMore();

      if (widget.onPostRefresh != null) {
        await widget.onPostRefresh!();
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
    _scrollController.dispose();
    super.dispose();
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
              actions: [
                if (widget.actions != null) ...widget.actions!,
                const SizedBox(width: 4),
              ],
            ),
          ],
          body: Column(
            children: [
              // ── 刷新进度指示条 ──
              if (_isRefreshing)
                LinearProgressIndicator(
                  minHeight: 3,
                  color: colorScheme.primary,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),

              // ── 主体内容 ──
              Expanded(child: _buildBody(colorScheme, textTheme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme, TextTheme textTheme) {
    // 首次加载 → 骨架屏
    if (_items.isEmpty && _isLoading) {
      return _buildSkeletonList(colorScheme);
    }

    // 空状态
    if (_items.isEmpty && !_isLoading) {
      return _buildEmptyState(colorScheme, textTheme);
    }

    // 数据列表
    final listView = ListView.builder(
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
        return widget.itemBuilder(
          context,
          _items[index],
          index,
          List.unmodifiable(_items),
        );
      },
    );

    if (widget.onRefresh != null) {
      return RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: 0,
        child: listView,
      );
    }

    return listView;
  }

  // ── 骨架屏 ──
  Widget _buildSkeletonList(ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 88),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.skeletonCount,
      itemBuilder: (context, index) => widget.skeletonBuilder(colorScheme),
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
