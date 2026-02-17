import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/feed_repo.dart';
import '../data/service/sync_service.dart';
import '../widgets/article_list_page.dart';

class FeedPage extends StatelessWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final feedRepo = context.read<FeedRepo>();
    final syncService = context.read<SyncService>();

    return ArticleListPage(
      title: '文章推送',
      loadArticles: (limit, offset) =>
          feedRepo.getLocalArticles(limit: limit, offset: offset),
      searchArticles: (query, limit, offset) =>
          feedRepo.searchLocalArticles(query, limit: limit, offset: offset),
      onFilter: () {
        // TODO: implement filter bottom sheet
      },
      onSettings: () {
        // TODO: implement settings
      },
      onRefresh: () => feedRepo.refreshArticles(),
      onPostRefresh: () => syncService.pullStatus(),
      emptyTitle: '暂无文章',
      emptySubtitle: '下拉刷新以获取最新内容',
      emptyActionLabel: '刷新',
    );
  }
}
