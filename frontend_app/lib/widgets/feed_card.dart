import 'package:flutter/material.dart';
import '../data/models/article_view_data.dart';
import '../data/models/article.dart';
import 'cached_image.dart';

class FeedItemCard extends StatelessWidget {
  final ArticleViewData articleViewData;
  final VoidCallback? onTap;

  FeedItemCard({super.key, required Article article, this.onTap})
    : articleViewData = ArticleViewData.fromArticle(article);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final hasImage =
        articleViewData.graphicalAbsUrl != null &&
        articleViewData.graphicalAbsUrl!.isNotEmpty;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      color: articleViewData.isRead
          ? colorScheme.surfaceContainerLowest.withValues(alpha: 0.6)
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: articleViewData.isRead ? 0.75 : 1.0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 文字内容 ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildMetadataRow(colorScheme, textTheme),
                      const SizedBox(height: 8),
                      Text(
                        articleViewData.displayTitle ??
                            articleViewData.article.title,
                        maxLines: hasImage ? 3 : 4,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          color: articleViewData.isRead
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildBottomRow(colorScheme, textTheme),
                    ],
                  ),
                ),

                // ── 缩略图 ──
                if (hasImage) ...[
                  const SizedBox(width: 14),
                  _buildThumbnail(colorScheme),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 期刊名 · 日期 ──
  Widget _buildMetadataRow(ColorScheme colorScheme, TextTheme textTheme) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: articleViewData.tagColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            [
              articleViewData.displayJournalName ??
                  articleViewData.article.journalName,
              if (articleViewData.publishedDate != null)
                articleViewData.publishedDate,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }

  // ── 标签 + 收藏指示器 ──
  Widget _buildBottomRow(ColorScheme colorScheme, TextTheme textTheme) {
    return Row(
      children: [
        if (articleViewData.displayMaintag != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              articleViewData.displayMaintag!,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w500,
                fontSize: 9,
              ),
            ),
          ),
        const Spacer(),
        if (articleViewData.isFavorite)
          Icon(Icons.favorite_rounded, size: 16, color: colorScheme.error),
      ],
    );
  }

  // ── 图片缩略图 ──
  Widget _buildThumbnail(ColorScheme colorScheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 100,
        height: 100,
        child: CachedArticleImage(
          articleId: articleViewData.article.articleId,
          imageUrl: articleViewData.graphicalAbsUrl!,
          fallbackImageUrl: articleViewData.graphicalAbsFallbackUrl,
          cachePath: articleViewData.graphicalAbsCachePath,
          fit: BoxFit.cover,
          width: 100,
          height: 100,
        ),
      ),
    );
  }
}
