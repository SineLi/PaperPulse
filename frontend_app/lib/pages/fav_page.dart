import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/feed_repo.dart';
import '../data/service/sync_service.dart';
import '../widgets/article_list_page.dart';

class FavPage extends StatelessWidget {
  const FavPage({super.key});

  @override
  Widget build(BuildContext context) {
    final feedRepo = context.read<FeedRepo>();
    final syncService = context.read<SyncService>();

    return ArticleListPage(
      title: '我的收藏',
      loadArticles: (limit, offset, filter) =>
          feedRepo.getLocalFavoriteArticles(
            limit: limit,
            offset: offset,
            filter: filter,
          ),
      searchArticles: (query, limit, offset) =>
          feedRepo.searchLocalArticles(query, limit: limit, offset: offset),
      onSettings: () {
        // TODO: implement settings
      },
      onRefresh: () async {
        await syncService.pullStatus();
        return 0;
      },
      loadFilterJournals: feedRepo.getFilterableJournals,
      loadFilterTags: feedRepo.getFilterableTags,
      emptyIcon: Icons.bookmark_border_rounded,
      emptyTitle: '暂无收藏',
      emptySubtitle: '收藏的文章会出现在这里',
      emptyActionLabel: null,
    );
  }
}
