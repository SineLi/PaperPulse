import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/feed_repo.dart';
import '../data/service/post_auth_sync_service.dart';
import '../data/service/sync_service.dart';
import '../navigation/tab_scroll_registry.dart';
import '../widgets/article_list_page.dart';
import '../widgets/feed_card.dart';

class FeedPage extends StatefulWidget {
  final ScrollController? scrollController;

  const FeedPage({super.key, this.scrollController});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  late FeedRepo _feedRepo;
  int? _lastSeenArticleId;
  int? _pendingSeenArticleId;
  Timer? _persistSeenTimer;
  Future<void> _persistSeenChain = Future.value();
  bool _isUserScrollInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadLastSeenBoundary());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _feedRepo = context.read<FeedRepo>();
  }

  Future<void> _loadLastSeenBoundary() async {
    final id = await _feedRepo.getLastSeenFeedArticleId();
    if (!mounted) return;
    setState(() {
      _lastSeenArticleId = id > 0 ? id : null;
    });
  }

  void _onArticleVisible(int articleId) {
    if (!_isUserScrollInProgress) return;
    _pendingSeenArticleId = articleId;
    _persistSeenTimer?.cancel();
    _persistSeenTimer = Timer(
      const Duration(milliseconds: 200),
      _persistPendingSeenArticle,
    );
  }

  void _onUserScrollStart() {
    _isUserScrollInProgress = true;
  }

  void _onUserScrollEnd() {
    _isUserScrollInProgress = false;
  }

  void _persistPendingSeenArticle() {
    final articleId = _pendingSeenArticleId;
    _pendingSeenArticleId = null;
    if (articleId == null) return;
    _persistSeenChain = _persistSeenChain.then(
      (_) => _feedRepo.setLastSeenFeedArticleId(articleId),
    );
    unawaited(_persistSeenChain);
  }

  @override
  void dispose() {
    _persistSeenTimer?.cancel();
    _persistPendingSeenArticle();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feedRepo = context.read<FeedRepo>();
    final syncService = context.read<SyncService>();
    final postAuthSyncService = context.watch<PostAuthSyncService>();

    return ArticleListPage(
      title: '文章推送',
      scrollController: widget.scrollController,
      tabScrollIndex: feedTabIndex,
      routeSource: 'feed',
      cardStyle: FeedCardStyle.masonry,
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
      lastSeenArticleId: _lastSeenArticleId,
      onArticleVisible: _onArticleVisible,
      onUserScrollStart: _onUserScrollStart,
      onUserScrollEnd: _onUserScrollEnd,
      loadFilterJournals: feedRepo.getFilterableJournals,
      loadFilterTags: feedRepo.getFilterableTags,
      emptyTitle: '暂无文章',
      emptySubtitle: '下拉刷新以获取最新内容',
      emptyActionLabel: '刷新',
    );
  }
}
