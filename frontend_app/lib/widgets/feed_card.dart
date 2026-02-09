import 'package:flutter/material.dart';
import '../data/models/article_view_data.dart';
import '../data/models/article.dart';

class FeedItemCard extends StatelessWidget {
  final ArticleViewData articleViewData;
  final VoidCallback? onTap;

  FeedItemCard({super.key, required Article article, this.onTap})
    : articleViewData = ArticleViewData.fromArticle(article);

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 140,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  color: colorScheme.secondaryContainer.withValues(alpha: .3),
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 8,
                            backgroundColor: articleViewData.tagColor,
                            child: Text(
                              articleViewData.displayJournalInitials,
                              style: TextStyle(
                                color: colorScheme.onPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: RichText(
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontSize: 10,
                                ),
                                children: [
                                  TextSpan(
                                    text:
                                        articleViewData.displayJournalName ??
                                        articleViewData.article.journalName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  TextSpan(
                                    text:
                                        " · ${articleViewData.publishedDate ?? ''}",
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        articleViewData.displayTitle ??
                            articleViewData.article.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          articleViewData.displayMaintag ?? 'Article',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 右侧预览区
              SizedBox(
                width: 150,
                child: Container(
                  // 使用最浅的容器色作为占位背景
                  color: colorScheme.surfaceContainerHighest,
                  child: Center(
                    child: Icon(
                      Icons.image,
                      size: 34,
                      color: colorScheme.outline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
