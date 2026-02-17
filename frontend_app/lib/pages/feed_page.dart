import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/feed_repo.dart';
import '../data/service/sync_service.dart';
import '../widgets/article_list_page.dart';

class FeedPage extends StatelessWidget {
  // final String username;
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final feedRepo = context.read<FeedRepo>();
    final syncService = context.read<SyncService>();

    return ArticleListPage(
      title: '文章推送',
      actions: [
        IconButton(
          icon: const Icon(Icons.filter_list),
          tooltip: '筛选',
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: '搜索',
          onPressed: () {
            // TODO: implement search
          },
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: '设置',
          onPressed: () {
            // TODO: implement profile
          },
        ),
      ],
      loadArticles: (limit, offset) =>
          feedRepo.getLocalArticles(limit: limit, offset: offset),
      onRefresh: () => feedRepo.refreshArticles(),
      onPostRefresh: () => syncService.pullStatus(),
      emptyTitle: '暂无文章',
      emptySubtitle: '下拉刷新以获取最新内容',
      emptyActionLabel: '刷新',
    );
  }
}
