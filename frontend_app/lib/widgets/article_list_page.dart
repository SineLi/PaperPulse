import 'package:flutter/material.dart';

import '../data/models/article.dart';
import 'feed_card.dart';

/// 加载文章的回调：返回指定分页的文章列表
typedef ArticleLoader = Future<List<Article>> Function(int limit, int offset);

/// 刷新文章的回调：返回新增文章数量
typedef ArticleRefresher = Future<int> Function();

/// 刷新成功后的提示文案生成器（传入新增数量，返回 SnackBar 文案；返回 null 则不提示）
typedef RefreshMessageBuilder = String? Function(int count);

/// 通用文章列表页，封装了分页加载、骨架屏、空状态和下拉刷新逻辑。
/// 可被 FeedPage、收藏页等复用。
class ArticleListPage extends StatefulWidget {
  /// AppBar 标题
  final String title;

  /// AppBar 右侧操作按钮
  final List<Widget>? actions;

  /// 加载文章数据的回调
  final ArticleLoader loadArticles;

  /// 下拉刷新回调（为 null 则禁用刷新）
  final ArticleRefresher? onRefresh;

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

  const ArticleListPage({
    super.key,
    required this.title,
    required this.loadArticles,
    this.actions,
    this.onRefresh,
    this.onPostRefresh,
    this.refreshMessageBuilder,
    this.emptyIcon = Icons.article_outlined,
    this.emptyTitle = '暂无文章',
    this.emptySubtitle = '下拉刷新以获取最新内容',
    this.emptyActionLabel = '刷新',
    this.pageSize = 20,
  });

  @override
  State<ArticleListPage> createState() => _ArticleListPageState();
}

class _ArticleListPageState extends State<ArticleListPage> {
  final ScrollController _scrollController = ScrollController();
  final List<Article> _articles = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _hasMore = true;
  int _currentOffset = 0;

  @override
  void initState() {
    super.initState();
    _loadMoreArticles();
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 300 &&
        !_isLoading &&
        _hasMore) {
      _loadMoreArticles();
    }
    return false;
  }

  Future<void> _loadMoreArticles() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final newArticles = await widget.loadArticles(
        widget.pageSize,
        _currentOffset,
      );

      if (mounted) {
        setState(() {
          _currentOffset += newArticles.length;
          _articles.addAll(newArticles);
          _hasMore = newArticles.length == widget.pageSize;
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

  Future<void> _refreshArticles() async {
    if (_isRefreshing || widget.onRefresh == null) return;

    setState(() => _isRefreshing = true);

    try {
      final count = await widget.onRefresh!();

      setState(() {
        _currentOffset = 0;
        _articles.clear();
        _hasMore = true;
        _isRefreshing = false;
      });

      await _loadMoreArticles();

      if (widget.onPostRefresh != null) {
        await widget.onPostRefresh!();
      }

      if (mounted && count > 0) {
        final message =
            widget.refreshMessageBuilder?.call(count) ?? '已更新 $count 篇新文章';
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
    if (_articles.isEmpty && _isLoading) {
      return _buildSkeletonList(colorScheme);
    }

    // 空状态
    if (_articles.isEmpty && !_isLoading) {
      return _buildEmptyState(colorScheme, textTheme);
    }

    // 文章列表
    final listView = ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 88),
      itemCount: _articles.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _articles.length) {
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
        return FeedItemCard(article: _articles[index]);
      },
    );

    if (widget.onRefresh != null) {
      return RefreshIndicator(
        onRefresh: _refreshArticles,
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
      itemCount: 6,
      itemBuilder: (context, index) => _SkeletonCard(colorScheme: colorScheme),
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
                onPressed: _refreshArticles,
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

// ── 骨架卡片 ──
class _SkeletonCard extends StatelessWidget {
  final ColorScheme colorScheme;
  const _SkeletonCard({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final bone = colorScheme.surfaceContainerHighest;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bone(bone, width: 140, height: 10),
                  const SizedBox(height: 12),
                  _bone(bone, height: 14),
                  const SizedBox(height: 6),
                  _bone(bone, height: 14),
                  const SizedBox(height: 6),
                  _bone(bone, width: 180, height: 14),
                  const SizedBox(height: 14),
                  _bone(bone, width: 64, height: 18, radius: 8),
                ],
              ),
            ),
            const SizedBox(width: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(width: 100, height: 100, color: bone),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bone(
    Color color, {
    double? width,
    required double height,
    double radius = 4,
  }) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
