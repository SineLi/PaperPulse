import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/feed_repo.dart';
import '../data/service/sync_service.dart';
import '../widgets/article_list_page.dart';

class FeedPage extends StatelessWidget {
  final ScrollController? scrollController;

  const FeedPage({super.key, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final feedRepo = context.read<FeedRepo>();
    final syncService = context.read<SyncService>();

    return ArticleListPage(
      title: '文章推送',
      scrollController: scrollController,
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
      loadFilterJournals: feedRepo.getFilterableJournals,
      loadFilterTags: feedRepo.getFilterableTags,
      emptyTitle: '暂无文章',
      emptySubtitle: '下拉刷新以获取最新内容',
      emptyActionLabel: '刷新',
    );
  }
}
