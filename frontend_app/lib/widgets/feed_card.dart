import 'package:flutter/material.dart';

import '../data/models/article.dart';
import '../data/models/article_view_data.dart';
import 'cached_image.dart';

enum FeedCardStyle { compact, featuredImage }

class FeedItemCard extends StatelessWidget {
  final ArticleViewData articleViewData;
  final VoidCallback? onTap;
  final bool dimWhenRead;
  final FeedCardStyle style;

  FeedItemCard({
    super.key,
    required Article article,
    this.onTap,
    this.dimWhenRead = true,
    this.style = FeedCardStyle.featuredImage,
  }) : articleViewData = ArticleViewData.fromArticle(article);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shouldDim = dimWhenRead && articleViewData.isRead;
    final borderRadius = BorderRadius.circular(
      style == FeedCardStyle.featuredImage ? 10 : 16,
    );

    return Card(
      key: ValueKey('feed-card-${style.name}'),
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      color: shouldDim
          ? colorScheme.surfaceContainerLowest.withValues(alpha: 0.6)
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: style == FeedCardStyle.featuredImage
            ? BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              )
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: shouldDim ? 0.75 : 1.0,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: switch (style) {
            FeedCardStyle.compact => _buildCompactCard(context, colorScheme),
            FeedCardStyle.featuredImage => _buildFeaturedImageCard(
              context,
              colorScheme,
            ),
          },
        ),
      ),
    );
  }

  Widget _buildCompactCard(BuildContext context, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    final hasImage =
        articleViewData.graphicalAbsUrl != null &&
        articleViewData.graphicalAbsUrl!.isNotEmpty;
    final shouldDim = dimWhenRead && articleViewData.isRead;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCompactMetadataRow(colorScheme, textTheme),
                const SizedBox(height: 8),
                Text(
                  articleViewData.displayTitle ?? articleViewData.article.title,
                  maxLines: hasImage ? 3 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: shouldDim
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                _buildCompactBottomRow(colorScheme, textTheme),
              ],
            ),
          ),
          if (hasImage) ...[const SizedBox(width: 14), _buildThumbnail()],
        ],
      ),
    );
  }

  Widget _buildFeaturedImageCard(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final imageUrl = articleViewData.graphicalAbsUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              _buildJournalAvatar(textTheme),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  articleViewData.displayJournalName ??
                      articleViewData.article.journalName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (articleViewData.publishedDate != null)
                Text(
                  articleViewData.publishedDate!,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(width: 8),
              Icon(
                articleViewData.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                key: const ValueKey('feed-card-favorite-icon'),
                size: 19,
                color: articleViewData.isFavorite
                    ? colorScheme.error
                    : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasImage)
                CachedArticleImage(
                  articleId: articleViewData.article.articleId,
                  imageUrl: imageUrl,
                  cachePath: articleViewData.graphicalAbsCachePath,
                  fit: BoxFit.cover,
                )
              else
                _buildFeaturedImagePlaceholder(colorScheme),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colorScheme.scrim.withValues(alpha: 0),
                      colorScheme.scrim.withValues(alpha: 0.82),
                    ],
                    stops: const [0.35, 1],
                  ),
                ),
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (articleViewData.displayMaintag != null &&
                        articleViewData.displayMaintag!.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh.withValues(
                            alpha: 0.92,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          articleViewData.displayMaintag!,
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      articleViewData.displayTitle ??
                          articleViewData.article.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturedImagePlaceholder(ColorScheme colorScheme) {
    final publisherColor = articleViewData.tagColor;
    final surface = colorScheme.surface;

    return DecoratedBox(
      key: const ValueKey('feed-card-placeholder-gradient'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(publisherColor, surface, 0.78)!,
            Color.lerp(publisherColor, surface, 0.58)!,
          ],
        ),
      ),
    );
  }

  Widget _buildJournalAvatar(TextTheme textTheme) {
    final avatarColor = articleViewData.tagColor;
    final avatarForeground =
        ThemeData.estimateBrightnessForColor(avatarColor) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: avatarColor, shape: BoxShape.circle),
      child: Text(
        articleViewData.displayJournalInitials,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: textTheme.labelSmall?.copyWith(
          color: avatarForeground,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildCompactMetadataRow(
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
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

  Widget _buildCompactBottomRow(ColorScheme colorScheme, TextTheme textTheme) {
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

  Widget _buildThumbnail() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 100,
        height: 100,
        child: CachedArticleImage(
          articleId: articleViewData.article.articleId,
          imageUrl: articleViewData.graphicalAbsUrl!,
          cachePath: articleViewData.graphicalAbsCachePath,
          fit: BoxFit.cover,
          width: 100,
          height: 100,
        ),
      ),
    );
  }
}
