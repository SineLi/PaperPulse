import 'package:flutter/material.dart';

import '../data/models/article.dart';
import '../pages/article_detail_page.dart';
import 'feed_card.dart';
import 'unified_list_page.dart';

/// 加载文章的回调：返回指定分页的文章列表
typedef ArticleLoader = Future<List<Article>> Function(int limit, int offset);

/// 搜索文章的回调
typedef ArticleSearcher =
    Future<List<Article>> Function(String query, int limit, int offset);

/// 文章列表页：基于 [UnifiedListPage] 的便捷封装，
/// 内置 FeedItemCard 和文章骨架屏。
class ArticleListPage extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final ArticleLoader loadArticles;
  final ArticleSearcher? searchArticles;
  final VoidCallback? onFilter;
  final bool filterActive;
  final VoidCallback? onSettings;
  final Future<int> Function()? onRefresh;
  final Future<void> Function()? onPostRefresh;
  final RefreshMessageBuilder? refreshMessageBuilder;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;
  final String? emptyActionLabel;
  final int pageSize;

  const ArticleListPage({
    super.key,
    required this.title,
    required this.loadArticles,
    this.actions,
    this.searchArticles,
    this.onFilter,
    this.filterActive = false,
    this.onSettings,
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
  Widget build(BuildContext context) {
    return UnifiedListPage<Article>(
      title: title,
      actions: actions,
      loadItems: loadArticles,
      searchItems: searchArticles,
      searchHint: '搜索文章标题、摘要、期刊…',
      onFilter: onFilter,
      filterActive: filterActive,
      onSettings: onSettings,
      onRefresh: onRefresh,
      onPostRefresh: onPostRefresh,
      refreshMessageBuilder: refreshMessageBuilder,
      emptyIcon: emptyIcon,
      emptyTitle: emptyTitle,
      emptySubtitle: emptySubtitle,
      emptyActionLabel: emptyActionLabel,
      pageSize: pageSize,
      skeletonCount: 6,
      skeletonBuilder: (cs) => _ArticleSkeletonCard(colorScheme: cs),
      itemBuilder: (ctx, article, index, allArticles, updateItem) {
        return FeedItemCard(
          article: article,
          onTap: () {
            Navigator.of(ctx).push(
              MaterialPageRoute(
                builder: (_) => ArticleDetailPage(
                  articles: allArticles,
                  initialIndex: index,
                  onArticleRead: (articleId) {
                    final idx = allArticles.indexWhere(
                      (a) => a.articleId == articleId,
                    );
                    if (idx != -1) {
                      updateItem(idx, allArticles[idx].copyWith(isRead: true));
                    }
                  },
                ),
              ),
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
