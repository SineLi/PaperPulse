import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models/article.dart';
import '../data/repositories/feed_repo.dart';
import '../data/service/sync_service.dart';

import '../widgets/feed_card.dart';

class FeedPage extends StatefulWidget {
  final String username;
  const FeedPage({super.key, required this.username});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final ScrollController _scrollController = ScrollController();
  final List<Article> _articles = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  static const int _limit = 20;

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
      final feedRepo = context.read<FeedRepo>();
      final newArticles = await feedRepo.getLocalArticles(
        limit: _limit,
        offset: _currentOffset,
      );

      if (mounted) {
        setState(() {
          _currentOffset += newArticles.length;
          _articles.addAll(newArticles);
          _hasMore = newArticles.length == _limit;
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
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);

    try {
      final feedRepo = context.read<FeedRepo>();
      final syncService = context.read<SyncService>();

      final count = await feedRepo.refreshArticles();

      setState(() {
        _currentOffset = 0;
        _articles.clear();
        _hasMore = true;
        _isRefreshing = false;
      });

      await _loadMoreArticles();
      await syncService.pullStatus();

      if (mounted && count > 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已更新 $count 篇新文章')));
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
              title: const Text('文章推送'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search_rounded),
                  tooltip: '搜索',
                  onPressed: () {
                    // TODO: implement search
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.account_circle_outlined),
                  tooltip: widget.username,
                  onPressed: () {
                    // TODO: implement profile
                  },
                ),
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
    return RefreshIndicator(
      onRefresh: _refreshArticles,
      edgeOffset: 0,
      child: ListView.builder(
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
      ),
    );
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
              Icons.article_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: .5),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无文章',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '下拉刷新以获取最新内容',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: .7),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: _refreshArticles,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('刷新'),
            ),
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
