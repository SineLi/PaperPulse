import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/feed_repo.dart';
import '../data/service/post_auth_sync_service.dart';
import '../data/service/sync_service.dart';
import '../widgets/article_list_page.dart';

class FavPage extends StatelessWidget {
  final ScrollController? scrollController;

  const FavPage({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final feedRepo = context.read<FeedRepo>();
    final syncService = context.read<SyncService>();
    final postAuthSyncService = context.watch<PostAuthSyncService>();

    return ArticleListPage(
      title: '我的收藏',
      scrollController: scrollController,
      loadArticles: (limit, offset, filter) =>
          feedRepo.getLocalFavoriteArticles(
            limit: limit,
            offset: offset,
            filter: filter,
          ),
      searchArticles: (query, limit, offset) =>
          feedRepo.searchLocalArticles(query, limit: limit, offset: offset),
      onSettings: () {},
      onRefresh: () async {
        await syncService.pullStatus();
        return 0;
      },
      showExternalRefreshing: postAuthSyncService.isSyncing,
      externalRefreshSignal: postAuthSyncService.completedSyncCount,
      loadFilterJournals: feedRepo.getFilterableJournals,
      loadFilterTags: feedRepo.getFilterableTags,
      emptyIcon: Icons.bookmark_border_rounded,
      emptyTitle: '暂无收藏',
      emptySubtitle: '收藏的文章会出现在这里',
      emptyActionLabel: null,
    );
  }
}
