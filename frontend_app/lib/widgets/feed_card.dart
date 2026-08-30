import 'package:flutter/material.dart';

import '../data/models/article.dart';
import '../data/models/article_view_data.dart';
import '../settings/feed_card_style.dart';
import 'cached_image.dart';

export '../settings/feed_card_style.dart';

class FeedItemCard extends StatelessWidget {
  static const _masonryCardMaxHeight = 320.0;
  static const _masonryImageMaxHeight = 184.0;
  static const _masonryTitleMaxCharacters = 23;

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
    final isImageLedStyle = style != FeedCardStyle.compact;
    final borderRadius = BorderRadius.circular(switch (style) {
      FeedCardStyle.compact => 16,
      FeedCardStyle.featuredImage => 10,
      FeedCardStyle.masonry => 8,
    });

    return Card(
      key: ValueKey('feed-card-${style.name}'),
      elevation: 0,
      margin: style == FeedCardStyle.masonry
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      color: shouldDim
          ? colorScheme.surfaceContainerLowest.withValues(alpha: 0.6)
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: isImageLedStyle
            ? BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              )
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        key: style == FeedCardStyle.masonry
            ? const ValueKey('feed-card-masonry-max-height')
            : null,
        constraints: style == FeedCardStyle.masonry
            ? const BoxConstraints(maxHeight: _masonryCardMaxHeight)
            : const BoxConstraints(),
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
              FeedCardStyle.masonry => _buildMasonryCard(context, colorScheme),
            },
          ),
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

  Widget _buildMasonryCard(BuildContext context, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    final imageUrl = articleViewData.graphicalAbsUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final shouldDim = dimWhenRead && articleViewData.isRead;

    return LayoutBuilder(
      builder: (context, constraints) {
        final imageHeight = _masonryImageHeightFor(constraints.maxWidth);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const ValueKey('feed-card-masonry-image'),
              height: imageHeight,
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
                  if (_hasMasonryMaintag)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _buildMasonryMaintag(colorScheme, textTheme),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _masonryTitle,
                    maxLines: 3,
                    overflow: TextOverflow.clip,
                    style: textTheme.titleSmall?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.28,
                      color: shouldDim
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      _buildJournalAvatar(textTheme, size: 22),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          articleViewData.displayJournalName ??
                              articleViewData.article.journalName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.copyWith(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        articleViewData.isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        key: const ValueKey('feed-card-favorite-icon'),
                        size: 18,
                        color: articleViewData.isFavorite
                            ? colorScheme.error
                            : colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  double get _masonryImageAspectRatio {
    return switch (articleViewData.article.articleId.abs() % 3) {
      0 => 4 / 5,
      1 => 1,
      _ => 5 / 4,
    };
  }

  double _masonryImageHeightFor(double width) {
    if (!width.isFinite) return _masonryImageMaxHeight;
    return (width / _masonryImageAspectRatio)
        .clamp(0.0, _masonryImageMaxHeight)
        .toDouble();
  }

  String get _masonryTitle {
    final title = articleViewData.displayTitle ?? articleViewData.article.title;
    return title.characters
        .getRange(
          0,
          title.characters.length.clamp(0, _masonryTitleMaxCharacters),
        )
        .toString();
  }

  bool get _hasMasonryMaintag =>
      articleViewData.displayMaintag != null &&
      articleViewData.displayMaintag!.isNotEmpty;

  Widget _buildMasonryMaintag(ColorScheme colorScheme, TextTheme textTheme) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 88),
      child: Container(
        key: const ValueKey('feed-card-masonry-maintag'),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          articleViewData.displayMaintag!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelSmall?.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildJournalAvatar(TextTheme textTheme, {double size = 34}) {
    final avatarColor = articleViewData.tagColor;
    final avatarForeground =
        ThemeData.estimateBrightnessForColor(avatarColor) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: avatarColor, shape: BoxShape.circle),
      child: Text(
        articleViewData.displayJournalInitials,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: textTheme.labelSmall?.copyWith(
          fontSize: size <= 24 ? 9 : null,
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
