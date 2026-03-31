import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/models/article.dart';
import '../data/models/article_filter.dart';
import 'article_filter_sheet.dart';
import 'feed_card.dart';
import 'unified_list_page.dart';

/// 加载文章的回调：返回指定分页的文章列表
typedef ArticleLoader =
    Future<List<Article>> Function(int limit, int offset, ArticleFilter filter);

/// 搜索文章的回调
typedef ArticleSearcher =
    Future<List<Article>> Function(String query, int limit, int offset);

/// 文章列表页：基于 [UnifiedListPage] 的便捷封装，
/// 内置 FeedItemCard、文章骨架屏和筛选面板。
class ArticleListPage extends StatefulWidget {
  final String title;
  final List<Widget>? actions;
  final ArticleLoader loadArticles;
  final ArticleSearcher? searchArticles;
  final VoidCallback? onSettings;
  final Future<int> Function()? onRefresh;
  final Future<void> Function()? onPostRefresh;
  final RefreshMessageBuilder? refreshMessageBuilder;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;
  final String? emptyActionLabel;
  final int pageSize;
  final ScrollController? scrollController;
  final int? tabScrollIndex;
  // 标记详情页是从哪个顶层列表进入的，例如 feed 或 favorites。
  final String routeSource;
  final bool autoRefreshOnInit;
  final bool showExternalRefreshing;
  final int externalRefreshSignal;

  /// 返回筛选面板可用的期刊列表（懒加载，首次打开面板时调用）
  final Future<List<({int id, String name, String abbr})>> Function()?
  loadFilterJournals;

  /// 返回筛选面板可用的标签列表（懒加载，首次打开面板时调用）
  final Future<List<String>> Function()? loadFilterTags;

  const ArticleListPage({
    super.key,
    required this.title,
    required this.loadArticles,
    this.actions,
    this.searchArticles,
    this.onSettings,
    this.onRefresh,
    this.onPostRefresh,
    this.refreshMessageBuilder,
    this.emptyIcon = Icons.article_outlined,
    this.emptyTitle = '暂无文章',
    this.emptySubtitle = '下拉刷新以获取最新内容',
    this.emptyActionLabel = '刷新',
    this.pageSize = 20,
    this.scrollController,
    this.tabScrollIndex,
    required this.routeSource,
    this.autoRefreshOnInit = false,
    this.showExternalRefreshing = false,
    this.externalRefreshSignal = 0,
    this.loadFilterJournals,
    this.loadFilterTags,
  });

  @override
  State<ArticleListPage> createState() => _ArticleListPageState();
}

class _ArticleListPageState extends State<ArticleListPage> {
  ArticleFilter _filter = ArticleFilter.empty;

  // 筛选面板数据缓存，首次打开时懒加载，避免每次打开都重新查询 DB
  List<({int id, String name, String abbr})>? _cachedJournals;
  List<String>? _cachedTags;

  Future<void> _openFilterSheet() async {
    // 首次打开时并行加载期刊和标签数据
    if (_cachedJournals == null || _cachedTags == null) {
      final results = await Future.wait([
        widget.loadFilterJournals?.call() ??
            Future.value(<({int id, String name, String abbr})>[]),
        widget.loadFilterTags?.call() ?? Future.value(<String>[]),
      ]);
      if (!mounted) return;
      _cachedJournals =
          results[0] as List<({int id, String name, String abbr})>;
      _cachedTags = results[1] as List<String>;
    }

    final result = await showArticleFilterSheet(
      context,
      current: _filter,
      journals: _cachedJournals!,
      tags: _cachedTags!,
    );
    if (result != null && mounted) {
      setState(() => _filter = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return UnifiedListPage<Article>(
      // filter 变化时，ValueKey 不同，Flutter 会销毁旧 State 并完整重建，
      // 从而自动触发 initState → _loadMore，实现筛选重置分页。
      key: ValueKey(_filter),
      title: widget.title,
      actions: widget.actions,
      loadItems: (limit, offset) => widget.loadArticles(limit, offset, _filter),
      searchItems: widget.searchArticles,
      searchHint: '搜索文章标题、摘要、期刊…',
      onFilter: _openFilterSheet,
      filterActive: _filter.isActive,
      onSettings: widget.onSettings,
      onRefresh: widget.onRefresh,
      onPostRefresh: widget.onPostRefresh,
      refreshMessageBuilder: widget.refreshMessageBuilder,
      emptyIcon: widget.emptyIcon,
      emptyTitle: widget.emptyTitle,
      emptySubtitle: widget.emptySubtitle,
      emptyActionLabel: widget.emptyActionLabel,
      pageSize: widget.pageSize,
      scrollController: widget.scrollController,
      tabScrollIndex: widget.tabScrollIndex,
      autoRefreshOnInit: widget.autoRefreshOnInit,
      showExternalRefreshing: widget.showExternalRefreshing,
      externalRefreshSignal: widget.externalRefreshSignal,
      skeletonCount: 6,
      skeletonBuilder: (cs) => _ArticleSkeletonCard(colorScheme: cs),
      itemBuilder: (ctx, article, index, allArticles, updateItem) {
        return FeedItemCard(
          article: article,
          onTap: () {
            // 路由里只放稳定、可刷新的状态。详情页会根据 articleId 查当前文章，
            // 再根据 source 在本地数据库里重建上一篇/下一篇的文章序列。
            ctx.go(
              '/article/${article.articleId}?source=${Uri.encodeQueryComponent(widget.routeSource)}',
              // extra: (int articleId) {
              //   // 这个回调不是详情页的硬依赖，只用于从列表页进入时顺手把
              //   // 当前列表项的已读状态同步回来。
              //   final idx = allArticles.indexWhere((a) => a.articleId == articleId);
              //   if (idx != -1) {
              //     updateItem(idx, allArticles[idx].copyWith(isRead: true));
              //   }
              // },
            );
          },
        );
      },
    );
  }
}

// ── 文章骨架卡片 ──
class _ArticleSkeletonCard extends StatelessWidget {
  final ColorScheme colorScheme;
  const _ArticleSkeletonCard({required this.colorScheme});

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
