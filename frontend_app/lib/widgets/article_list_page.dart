import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../data/models/article.dart';
import '../data/models/article_filter.dart';
import '../data/models/article_detail_callbacks.dart';
import '../navigation/tab_scroll_registry.dart';
import 'article_filter_sheet.dart';
import 'feed_card.dart';
import 'last_read_marker.dart';
import 'unified_list_page.dart';

/// 加载文章的回调：返回指定分页的文章列表
typedef ArticleLoader =
    Future<List<Article>> Function(int limit, int offset, ArticleFilter filter);

/// 搜索文章的回调
typedef ArticleSearcher =
    Future<List<Article>> Function(String query, int limit, int offset);

/// 文章列表页：基于 [UnifiedListPage] 的便捷封装，
/// 内置 FeedItemCard、文章骨架屏和筛选面板。
class ArticleListPage extends StatefulWidget {
  final String title;
  final List<Widget>? actions;
  final ArticleLoader loadArticles;
  final ArticleSearcher? searchArticles;
  final VoidCallback? onSettings;
  final Future<int> Function()? onRefresh;
  final Future<void> Function()? onPostRefresh;
  final RefreshMessageBuilder? refreshMessageBuilder;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;
  final String? emptyActionLabel;
  final int pageSize;
  final ScrollController? scrollController;
  final int? tabScrollIndex;
  // 标记详情页是从哪个顶层列表进入的，例如 feed 或 favorites。
  final String routeSource;
  final bool autoRefreshOnInit;
  final bool showExternalRefreshing;
  final int externalRefreshSignal;
  final bool dimReadArticles;
  final int? lastSeenArticleId;
  final void Function(int articleId)? onArticleVisible;
  final VoidCallback? onUserScrollStart;
  final VoidCallback? onUserScrollEnd;

  /// 返回筛选面板可用的期刊列表（懒加载，首次打开面板时调用）
  final Future<List<({int id, String name, String abbr})>> Function()?
  loadFilterJournals;

  /// 返回筛选面板可用的标签列表（懒加载，首次打开面板时调用）
  final Future<List<String>> Function()? loadFilterTags;

  const ArticleListPage({
    super.key,
    required this.title,
    required this.loadArticles,
    this.actions,
    this.searchArticles,
    this.onSettings,
    this.onRefresh,
    this.onPostRefresh,
    this.refreshMessageBuilder,
    this.emptyIcon = Icons.article_outlined,
    this.emptyTitle = '暂无文章',
    this.emptySubtitle = '下拉刷新以获取最新内容',
    this.emptyActionLabel = '刷新',
    this.pageSize = 20,
    this.scrollController,
    this.tabScrollIndex,
    required this.routeSource,
    this.autoRefreshOnInit = false,
    this.showExternalRefreshing = false,
    this.externalRefreshSignal = 0,
    this.dimReadArticles = true,
    this.lastSeenArticleId,
    this.onArticleVisible,
    this.onUserScrollStart,
    this.onUserScrollEnd,
    this.loadFilterJournals,
    this.loadFilterTags,
  });

  @override
  State<ArticleListPage> createState() => _ArticleListPageState();
}

class _ArticleListPageState extends State<ArticleListPage> {
  ArticleFilter _filter = ArticleFilter.empty;
  final GlobalKey _lastReadMarkerKey = GlobalKey();
  TabScrollRegistry? _tabScrollRegistry;
  int _lastReadMarkerIndex = -1;
  int _loadedArticleCount = 0;
  final Map<int, int> _visibleArticleIndexes = {};
  final List<VoidCallback> _pendingVisibilityFlushes = [];
  bool _visibilityFlushScheduled = false;

  // 筛选面板数据缓存，首次打开时懒加载，避免每次打开都重新查询 DB
  List<({int id, String name, String abbr})>? _cachedJournals;
  List<String>? _cachedTags;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = context.read<TabScrollRegistry>();
    if (_tabScrollRegistry == registry) return;

    final tabIndex = widget.tabScrollIndex;
    if (_tabScrollRegistry != null && tabIndex != null) {
      _tabScrollRegistry!.unregisterBoundaryScroller(
        tabIndex,
        _scrollToLastReadMarker,
      );
    }
    _tabScrollRegistry = registry;
    if (tabIndex != null) {
      registry.registerBoundaryScroller(tabIndex, _scrollToLastReadMarker);
    }
  }

  void _notifyLastVisibleArticle() {
    final onArticleVisible = widget.onArticleVisible;
    if (onArticleVisible == null || _visibleArticleIndexes.isEmpty) return;
    final lastVisible = _visibleArticleIndexes.entries.reduce(
      (current, next) => current.value > next.value ? current : next,
    );
    onArticleVisible(lastVisible.key);
  }

  void _handleUserScrollStart() {
    _scheduleVisibilityFlush(() {
      // 先结算启动布局留下的回调，此时 Feed 尚未允许更新边界。
      VisibilityDetectorController.instance.notifyNow();
      widget.onUserScrollStart?.call();
      // 即使一次很短的手势在刷新前已经结束，也要把刚结算出的
      // 最后可见文章纳入这次用户滚动。
      _notifyLastVisibleArticle();
    });
  }

  void _handleUserScrollEnd() {
    _scheduleVisibilityFlush(() {
      // 在关闭用户滚动写入窗口前，结算手势的最终曝光位置。
      VisibilityDetectorController.instance.notifyNow();
      _notifyLastVisibleArticle();
      widget.onUserScrollEnd?.call();
    });
  }

  void _scheduleVisibilityFlush(VoidCallback flush) {
    // ScrollNotification 可能在布局阶段派发。notifyNow() 会同步读取
    // RenderVisibilityDetector 的尺寸，必须放到帧与帧之间执行。
    _pendingVisibilityFlushes.add(flush);
    if (_visibilityFlushScheduled) return;
    _visibilityFlushScheduled = true;
    SchedulerBinding.instance.scheduleTask<void>(
      () {
        _visibilityFlushScheduled = false;
        if (!mounted) {
          _pendingVisibilityFlushes.clear();
          return;
        }

        // 同一帧内可能连续收到 start/end；按通知原始顺序结算，避免
        // 很短的手势先关闭再开启 Feed 的边界写入窗口。
        final pending = List<VoidCallback>.of(_pendingVisibilityFlushes);
        _pendingVisibilityFlushes.clear();
        for (final callback in pending) {
          callback();
        }
      },
      Priority.touch,
      debugLabel: 'flush article visibility',
    );
  }

  Future<bool> _scrollToLastReadMarker() async {
    var markerContext = _lastReadMarkerKey.currentContext;
    final tabIndex = widget.tabScrollIndex;
    if (markerContext == null &&
        tabIndex != null &&
        _lastReadMarkerIndex >= 0 &&
        _loadedArticleCount > 1) {
      await _tabScrollRegistry?.scrollToFraction(
        tabIndex,
        _lastReadMarkerIndex / (_loadedArticleCount - 1),
      );
      await WidgetsBinding.instance.endOfFrame;
      markerContext = _lastReadMarkerKey.currentContext;
    }
    if (!mounted || markerContext == null || !markerContext.mounted) {
      return false;
    }

    final renderObject = markerContext.findRenderObject();
    final scrollable = Scrollable.maybeOf(markerContext);
    if (renderObject == null || scrollable == null) {
      return false;
    }
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    if (viewport == null) return false;

    final position = scrollable.position;
    final revealedOffset = viewport
        .getOffsetToReveal(renderObject, 0.92)
        .offset;
    final targetOffset = revealedOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    await position.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
    return true;
  }

  @override
  void dispose() {
    final tabIndex = widget.tabScrollIndex;
    if (tabIndex != null) {
      _tabScrollRegistry?.unregisterBoundaryScroller(
        tabIndex,
        _scrollToLastReadMarker,
      );
    }
    super.dispose();
  }

  Future<void> _openFilterSheet() async {
    // 首次打开时并行加载期刊和标签数据
    if (_cachedJournals == null || _cachedTags == null) {
      final results = await Future.wait([
        widget.loadFilterJournals?.call() ??
            Future.value(<({int id, String name, String abbr})>[]),
        widget.loadFilterTags?.call() ?? Future.value(<String>[]),
      ]);
      if (!mounted) return;
      _cachedJournals =
          results[0] as List<({int id, String name, String abbr})>;
      _cachedTags = results[1] as List<String>;
    }

    final result = await showArticleFilterSheet(
      context,
      current: _filter,
      journals: _cachedJournals!,
      tags: _cachedTags!,
    );
    if (result != null && mounted) {
      setState(() => _filter = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return UnifiedListPage<Article>(
      // filter 变化时，ValueKey 不同，Flutter 会销毁旧 State 并完整重建，
      // 从而自动触发 initState → _loadMore，实现筛选重置分页。
      key: ValueKey(_filter),
      title: widget.title,
      actions: widget.actions,
      loadItems: (limit, offset) => widget.loadArticles(limit, offset, _filter),
      searchItems: widget.searchArticles,
      searchHint: '搜索文章标题、摘要、期刊…',
      onFilter: _openFilterSheet,
      filterActive: _filter.isActive,
      onSettings: widget.onSettings,
      onRefresh: widget.onRefresh,
      onPostRefresh: widget.onPostRefresh,
      refreshMessageBuilder: widget.refreshMessageBuilder,
      emptyIcon: widget.emptyIcon,
      emptyTitle: widget.emptyTitle,
      emptySubtitle: widget.emptySubtitle,
      emptyActionLabel: widget.emptyActionLabel,
      pageSize: widget.pageSize,
      scrollController: widget.scrollController,
      tabScrollIndex: widget.tabScrollIndex,
      autoRefreshOnInit: widget.autoRefreshOnInit,
      showExternalRefreshing: widget.showExternalRefreshing,
      externalRefreshSignal: widget.externalRefreshSignal,
      onUserScrollStart: _handleUserScrollStart,
      onUserScrollEnd: _handleUserScrollEnd,
      preloadAnchorKey: _filter.isActive ? null : widget.lastSeenArticleId,
      matchesPreloadAnchor: _filter.isActive || widget.lastSeenArticleId == null
          ? null
          : (article) => article.articleId == widget.lastSeenArticleId,
      skeletonCount: 6,
      skeletonBuilder: (cs) => _ArticleSkeletonCard(colorScheme: cs),
      itemBuilder:
          (
            ctx,
            article,
            index,
            allArticles,
            updateItem,
            updateItemById,
            removeItemById,
          ) {
            Widget card = FeedItemCard(
              article: article,
              dimWhenRead: widget.dimReadArticles,
              onTap: () {
                // 路由里只放稳定、可刷新的状态。详情页会根据 articleId 查当前文章，
                // 再根据 source 在本地数据库里重建上一篇/下一篇的文章序列。
                ctx.push(
                  '/article/${article.articleId}?source=${Uri.encodeQueryComponent(widget.routeSource)}',
                  // 为详情页提供已读回调，使其在标记已读时按 articleId 实时查找并更新当前列表项。
                  // 这样即使列表在打开详情期间发生变化，也能准确更新对应文章项。
                  extra: ArticleDetailCallbacks(
                    onArticleRead: (readArticleId) {
                      updateItemById(
                        readArticleId,
                        (readArticle) => readArticle.copyWith(isRead: true),
                      );
                    },
                    onFavoriteChanged: (favoriteArticleId, isFavorite) {
                      if (widget.routeSource == 'favorites' && !isFavorite) {
                        removeItemById(favoriteArticleId);
                        return;
                      }
                      updateItemById(
                        favoriteArticleId,
                        (favoriteArticle) =>
                            favoriteArticle.copyWith(isFavorite: isFavorite),
                      );
                    },
                  ),
                );
              },
            );

            if (widget.onArticleVisible != null) {
              card = VisibilityDetector(
                key: ValueKey('article-visibility-${article.articleId}'),
                onVisibilityChanged: (info) {
                  if (info.visibleFraction > 0) {
                    _visibleArticleIndexes[article.articleId] = index;
                  } else {
                    _visibleArticleIndexes.remove(article.articleId);
                  }
                  _notifyLastVisibleArticle();
                },
                child: card,
              );
            }

            final boundary = widget.lastSeenArticleId;
            final markerIndex = boundary == null
                ? -1
                : allArticles.indexWhere((item) => item.articleId == boundary);
            _lastReadMarkerIndex = markerIndex;
            _loadedArticleCount = allArticles.length;
            final showLastReadMarker = markerIndex >= 0 && index == markerIndex;
            if (!showLastReadMarker) return card;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LastReadMarker(key: _lastReadMarkerKey),
                card,
              ],
            );
          },
    );
  }
}

// ── 文章骨架卡片 ──
class _ArticleSkeletonCard extends StatelessWidget {
  final ColorScheme colorScheme;
  const _ArticleSkeletonCard({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final bone = colorScheme.surfaceContainerHighest;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                _bone(bone, width: 34, height: 34, radius: 17),
                const SizedBox(width: 10),
                Expanded(child: _bone(bone, width: 112, height: 12)),
                const SizedBox(width: 24),
                _bone(bone, width: 42, height: 10),
                const SizedBox(width: 14),
                _bone(bone, width: 18, height: 18, radius: 9),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(color: bone),
          ),
        ],
      ),
    );
  }

  Widget _bone(
    Color color, {
    double? width,
    required double height,
    double radius = 4,
  }) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
