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
          feedRepo.getLocalFavoriteArticles(limit: limit, offset: offset),
      onRefresh: () async {
        await syncService.pullStatus();
        return 0; // pullStatus 不返回新增数量，返回 0 跳过提示
      },
      emptyIcon: Icons.bookmark_border_rounded,
      emptyTitle: '暂无收藏',
      emptySubtitle: '收藏的文章会出现在这里',
      emptyActionLabel: null, // 空状态不显示刷新按钮
    );
  }
}
