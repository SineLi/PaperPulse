import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/feed_repo.dart';
import '../data/service/post_auth_sync_service.dart';
import '../data/service/sync_service.dart';
import '../navigation/tab_scroll_registry.dart';
import '../widgets/article_list_page.dart';

class FeedPage extends StatelessWidget {
  final ScrollController? scrollController;

  const FeedPage({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final feedRepo = context.read<FeedRepo>();
    final syncService = context.read<SyncService>();
    final postAuthSyncService = context.watch<PostAuthSyncService>();

    return ArticleListPage(
      title: '文章推送',
      scrollController: scrollController,
      tabScrollIndex: feedTabIndex,
      routeSource: 'feed',
      loadArticles: (limit, offset, filter) => feedRepo.getLocalArticles(
        limit: limit,
        offset: offset,
        filter: filter,
      ),
      searchArticles: (query, limit, offset) =>
          feedRepo.searchLocalArticles(query, limit: limit, offset: offset),
      onSettings: () {},
      onRefresh: () => feedRepo.refreshArticles(),
      onPostRefresh: () => syncService.pullStatus(),
      showExternalRefreshing: postAuthSyncService.isSyncing,
      externalRefreshSignal: postAuthSyncService.completedSyncCount,
      loadFilterJournals: feedRepo.getFilterableJournals,
      loadFilterTags: feedRepo.getFilterableTags,
      emptyTitle: '暂无文章',
      emptySubtitle: '下拉刷新以获取最新内容',
      emptyActionLabel: '刷新',
    );
  }
}
