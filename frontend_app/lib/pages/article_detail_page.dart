import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models/article_view_data.dart';
import '../data/db/articledb.dart';
import '../settings/settings_controller.dart';
import '../widgets/cached_image.dart';

const articleSourceFeed = 'feed';
const articleSourceFavorites = 'favorites';

// 目前只支持少数几个固定来源，用来在详情页里重建上一篇/下一篇的文章 ID 列表。
String normalizeArticleSource(String? source) {
  switch (source?.toLowerCase()) {
    case articleSourceFavorites:
      return articleSourceFavorites;
    case articleSourceFeed:
    default:
      return articleSourceFeed;
  }
}

/// 文章详情页
///
/// [articles] 当前文章列表，用于上一篇 / 下一篇导航
/// [initialIndex] 当前文章在列表中的索引
/// 基于路由参数驱动的文章详情页。
class ArticleDetailPage extends StatefulWidget {
  final int articleId;
  final String source; // 用于分析入口来源
  // 可选回调：从列表页进入时，用来同步更新发起页的已读状态。
  final void Function(int articleId)? onArticleRead;

  const ArticleDetailPage({
    super.key,
    required this.articleId,
    required this.source,
    this.onArticleRead,
  });

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  late ArticleViewData _viewData;
  final Map<int, ArticleViewData> _articleViewCache = <int, ArticleViewData>{};
  bool _hasData = false;
  bool _isLoading = true;
  String? _loadFailureMessage;
  List<int> _articleIds = const <int>[];
  int _currentPosition = 0;
  late ScrollController _scrollController;
  final Set<int> _markedAsRead = <int>{};
  bool _barsVisible = true;
  double _lastScrollOffset = 0;
  late bool _isFavorite;
  bool _suppressScrollListener = false;
  late ValueKey<int> _contentKey;
  bool _animateContentSwitch = false;
  int _transitionDirection = 1;
  double _gestureOverscroll = 0;
  int? _pendingGestureDirection;
  bool _showReleaseHint = false;
  bool _gestureHapticFired = false;
  bool _pointerIsDown = false;

  @override
  void initState() {
    super.initState();
    _contentKey = ValueKey(widget.articleId);
    _isFavorite = false;
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  Future<void> _loadInitialData() async {
    // 从本地数据库重建当前来源下的文章 ID 列表，这样无论是直达 URL
    // 还是页面刷新，详情页都仍然知道如何切换上一篇/下一篇。
    try {
      final ids = await _loadSourceArticleIds();
      if (!mounted) return;

      if (ids.isEmpty) {
        _articleIds = <int>[widget.articleId];
        await _showArticle(widget.articleId, position: 0, animate: false);
        _markAsReadAsync();
        return;
      }

      final position = ids.indexOf(widget.articleId);
      if (position == -1) {
        _articleIds = <int>[widget.articleId];
        await _showArticle(widget.articleId, position: 0, animate: false);
        _markAsReadAsync();
        return;
      }

      _articleIds = ids;
      await _showArticle(widget.articleId, position: position, animate: false);
      _markAsReadAsync();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailureMessage = '文章加载失败，请稍后重试。';
      });
    }
  }

  Future<List<int>> _loadSourceArticleIds() async {
    final db = context.read<ArticleDatabaseIO>();
    switch (normalizeArticleSource(widget.source)) {
      case articleSourceFavorites:
        return db.getFavoriteArticleIdsInOrder();
      case articleSourceFeed:
      default:
        return db.getAllArticleIds();
    }
  }

  Future<ArticleViewData?> _loadArticleView(int id) async {
    final cachedView = _articleViewCache[id];
    if (cachedView != null) return cachedView;
    final db = context.read<ArticleDatabaseIO>();
    // 按文章 ID 现场查库，不再依赖列表页传进来的内存文章列表。
    final article = await db.getArticle(id);
    if (article == null) return null;
    final view = ArticleViewData.fromArticle(article);
    _articleViewCache[id] = view;
    return view;
  }

  Future<void> _showArticle(
    int id, {
    required int position,
    required bool animate,
    int transitionDirection = 1,
  }) async {
    final view = await _loadArticleView(id);
    if (!mounted) return;
    if (view == null) {
      setState(() {
        _isLoading = false;
        _hasData = false;
        _loadFailureMessage = '未找到 ID 为 $id 的文章，可能已被删除或尚未同步。';
      });
      return;
    }

    if (animate &&
        _scrollController.hasClients &&
        _scrollController.offset != 0) {
      _suppressScrollListener = true;
      try {
        _scrollController.jumpTo(0);
      } finally {
        _suppressScrollListener = false;
      }
    }

    setState(() {
      _currentPosition = position;
      _viewData = view;
      _isFavorite = view.isFavorite;
      _contentKey = ValueKey(id);
      _hasData = true;
      _isLoading = false;
      _loadFailureMessage = null;
      _barsVisible = true;
      _lastScrollOffset = 0;
      _transitionDirection = transitionDirection;
      _animateContentSwitch = animate;
    });
    await _markAsRead();
  }

  Future<void> _navigateToPosition(int nextPosition) async {
    // 下一篇从下往上进入，上一篇从上往下进入。
    final transitionDirection = nextPosition > _currentPosition ? 1 : -1;
    if (nextPosition < 0 || nextPosition >= _articleIds.length) return;
    // 切换文章时总是回到顶部，避免保留上一篇的滚动位置。
    await _showArticle(
      _articleIds[nextPosition],
      position: nextPosition,
      animate: true,
      transitionDirection: transitionDirection,
    );
  }

  void _onScroll() {
    if (_suppressScrollListener) {
      _lastScrollOffset = _scrollController.offset;
      return;
    }
    final offset = _scrollController.offset;
    final delta = offset - _lastScrollOffset;
    if (delta > 8 && _barsVisible) {
      setState(() => _barsVisible = false);
    } else if (delta < -8 && !_barsVisible) {
      setState(() => _barsVisible = true);
    }
    _lastScrollOffset = offset;
  }

  /// 监听滚动：达到阈值时振动提示并显示 hint，松手时才真正切换
  void _resetGestureTracking() {
    _gestureOverscroll = 0;
    _pendingGestureDirection = null;
    _showReleaseHint = false;
    _gestureHapticFired = false;
  }

  void _setGestureHint(int? direction, bool visible) {
    if (_pendingGestureDirection == direction && _showReleaseHint == visible) {
      return;
    }
    setState(() {
      _pendingGestureDirection = direction;
      _showReleaseHint = visible;
    });
  }

  bool _canSwipeToDirection(int direction, AppSetting settings) {
    if (direction < 0) {
      return settings.swipeToChangeArticleUp && _currentPosition > 0;
    }
    return settings.swipeToChangeArticleDown &&
        _currentPosition < _articleIds.length - 1;
  }

  Future<void> _commitGestureNavigation(int direction) async {
    if (direction < 0) {
      await _navigateToPosition(_currentPosition - 1);
    } else {
      await _navigateToPosition(_currentPosition + 1);
    }
  }

  Future<void> _triggerPendingGestureNavigation() async {
    final settings = context.read<SettingsController>().setting;
    final direction = _pendingGestureDirection;
    final reachedThreshold =
        direction != null &&
        _gestureOverscroll >= settings.swipeSensitivity &&
        _canSwipeToDirection(direction, settings);
    _pointerIsDown = false;
    _resetGestureTracking();
    if (reachedThreshold) {
      await _commitGestureNavigation(direction);
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    final settings = context.read<SettingsController>().setting;

    if (notification is ScrollStartNotification) {
      _resetGestureTracking();
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      if (!_pointerIsDown || notification.dragDetails == null) {
        return false;
      }

      final metrics = notification.metrics;
      int? direction;
      double overscroll = 0;

      if (metrics.pixels < metrics.minScrollExtent) {
        direction = -1;
        overscroll = metrics.minScrollExtent - metrics.pixels;
      } else if (metrics.pixels > metrics.maxScrollExtent) {
        direction = 1;
        overscroll = metrics.pixels - metrics.maxScrollExtent;
      }

      if (direction == null || !_canSwipeToDirection(direction, settings)) {
        _resetGestureTracking();
        return false;
      }

      if (_pendingGestureDirection != direction) {
        _gestureOverscroll = overscroll;
        _gestureHapticFired = false;
        _pendingGestureDirection = direction;
      } else {
        _gestureOverscroll = overscroll;
      }

      if (!_gestureHapticFired &&
          _gestureOverscroll >= settings.swipeSensitivity) {
        _gestureHapticFired = true;
        HapticFeedback.selectionClick();
      }
      _setGestureHint(
        direction,
        _gestureOverscroll >= settings.swipeSensitivity,
      );
      return false;
    }

    return false;
  }

  /// 分离的异步已读标记，失败时按异常类型处理而非阻塞主流程
  void _markAsReadAsync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _markAsRead();
      }
    });
  }

  Future<void> _markAsRead() async {
    if (!_hasData) return;
    if (_viewData.isRead || _markedAsRead.contains(_viewData.id)) return;
    _markedAsRead.add(_viewData.id);
    final db = context.read<ArticleDatabaseIO>();
    try {
      await db.setReadWithSync(_viewData.id, true);
      final updatedView = ArticleViewData.fromArticle(
        _viewData.article.copyWith(isRead: true),
      );
      _articleViewCache[_viewData.id] = updatedView;
      _viewData = updatedView;
      widget.onArticleRead?.call(_viewData.id);
    } catch (e) {
      // 按异常类型分别处理，不阻塞阅读流程
      _markedAsRead.remove(_viewData.id);
      if (e is Exception) {
        // 网络、数据库等异常仅记录，不影响已显示内容
        debugPrint('标记已读失败: $e');
      }
      // 不 rethrow，让已读失败成为非关键路径
    }
  }

  Future<void> _toggleFavorite() async {
    if (!_hasData) return;
    final db = context.read<ArticleDatabaseIO>();
    final newState = !_isFavorite;
    await db.setFavoriteWithSync(_viewData.id, newState);
    if (mounted) {
      final updatedView = ArticleViewData.fromArticle(
        _viewData.article.copyWith(isFavorite: newState),
      );
      _articleViewCache[_viewData.id] = updatedView;
      setState(() {
        _viewData = updatedView;
        _isFavorite = newState;
      });
    }
  }

  void _shareDoi() {
    if (!_hasData) return;
    final doi = _viewData.article.doi;
    if (doi.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('该文章没有 DOI')));
      return;
    }
    SharePlus.instance.share(
      ShareParams(
        text:
            '${_viewData.displayJournalName} | ${_viewData.displayTitle ?? _viewData.article.title}: \n https://doi.org/$doi',
      ),
    );
  }

  void _openInBrowser() {
    if (!_hasData) return;
    final doi = _viewData.article.doi;
    if (doi.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无有效链接')));
      return;
    }
    final url = 'https://doi.org/$doi';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final settings = context.watch<SettingsController>().setting;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_hasData) {
      return ArticleNotFoundPage(message: _loadFailureMessage);
    }

    return Scaffold(
      body: Stack(
        children: [
          // ── 主要内容 ──
          Listener(
            onPointerDown: (_) => _pointerIsDown = true,
            onPointerUp: (_) => _triggerPendingGestureNavigation(),
            onPointerCancel: (_) => _triggerPendingGestureNavigation(),
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  // AppBar — floating + snap，向下滚动隐藏，向上微滑即回
                  SliverAppBar(
                    floating: true,
                    snap: true,
                    title: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.open_in_browser_rounded),
                        tooltip: '在浏览器中打开',
                        onPressed: _openInBrowser,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),

                  // 正文 — 带上下切换动画
                  SliverToBoxAdapter(
                    child: _buildArticleSwitchTransition(
                      animate: _animateContentSwitch,
                      child: RepaintBoundary(
                        key: _contentKey,
                        child: _buildArticleContent(
                          colorScheme,
                          textTheme,
                          settings,
                          key: _contentKey,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── 底部功能栏 ──
          Positioned(
            left: 0,
            right: 0,
            bottom: _pendingGestureDirection == 1 ? 0 : null,
            top: _pendingGestureDirection == -1 ? 0 : null,
            child: IgnorePointer(
              ignoring: true,
              child: SafeArea(
                bottom: _pendingGestureDirection == 1,
                top: _pendingGestureDirection == -1,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _showReleaseHint ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.inverseSurface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _pendingGestureDirection == -1
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: colorScheme.onInverseSurface,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _pendingGestureDirection == -1
                                ? '松手切换上一篇'
                                : '松手切换下一篇',
                            style: TextStyle(
                              color: colorScheme.onInverseSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSlide(
              offset: _barsVisible ? Offset.zero : const Offset(0, 1),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: _buildBottomBar(colorScheme, textTheme),
            ),
          ),
        ],
      ),
    );
  }

  // ── 文章正文内容（独立 widget 方便做 AnimatedSwitcher） ──
  // 只给新内容做入场动画，避免同时渲染两棵较重的内容树。
  Widget _buildArticleSwitchTransition({
    required Widget child,
    required bool animate,
  }) {
    if (!animate) return child;

    return TweenAnimationBuilder<double>(
      key: _contentKey,
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) {
        final translateY = (1 - value) * 42 * _transitionDirection;
        final opacity = 0.78 + (0.22 * value);
        return Transform.translate(
          offset: Offset(0, translateY),
          child: Opacity(opacity: opacity, child: child),
        );
      },
    );
  }

  // Article body content.
  Widget _buildArticleContent(
    ColorScheme colorScheme,
    TextTheme textTheme,
    AppSetting settings, {
    required Key key,
  }) {
    return KeyedSubtree(
      key: key,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),

            // ── 期刊 · 日期 ──
            _buildMetadataRow(colorScheme, textTheme),
            const SizedBox(height: 18),

            // ── 标题 ──
            Text(
              _viewData.displayTitle ?? _viewData.article.title,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: settings.titleBold
                    ? FontWeight.w800
                    : FontWeight.w400,
                fontSize: settings.titleFontSize.toDouble(),
                height: 1.4,
                letterSpacing: -0.3,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 14),

            // ── DOI ──
            if (_viewData.article.doi.isNotEmpty)
              _buildDoiRow(colorScheme, textTheme),

            const SizedBox(height: 14),

            // ── 标签 ──
            _buildTags(colorScheme, textTheme),

            const SizedBox(height: 24),
            Divider(color: colorScheme.outlineVariant, height: 1),
            const SizedBox(height: 24),

            // 一句话总结
            if (_viewData.displayOneStanceSum != null &&
                _viewData.displayOneStanceSum!.isNotEmpty)
              _buildOneStanceSummary(colorScheme, textTheme, settings),

            // 背景
            if (_viewData.displayBackground != null &&
                _viewData.displayBackground!.isNotEmpty)
              _buildSection(
                '背景',
                _viewData.displayBackground!,
                colorScheme,
                textTheme,
                settings,
              ),

            // ── 摘要 / 正文 ──
            if (_viewData.displaySummary != null &&
                _viewData.displaySummary!.isNotEmpty)
              _buildSection(
                '总结',
                _viewData.displaySummary!,
                colorScheme,
                textTheme,
                settings,
              ),

            // ── 创新点 ──
            if (_viewData.displayInnovations != null &&
                _viewData.displayInnovations!.isNotEmpty)
              _buildInnovations(colorScheme, textTheme, settings),

            // ── 图形摘要 ──
            if (_viewData.graphicalAbsUrl != null &&
                _viewData.graphicalAbsUrl!.isNotEmpty)
              _buildGraphicalAbstract(colorScheme, textTheme, settings),

            // 底部留白
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  // ── 期刊 · 日期行 ──
  Widget _buildMetadataRow(ColorScheme colorScheme, TextTheme textTheme) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _viewData.tagColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            [
              _viewData.displayJournalName ?? _viewData.article.journalName,
              if (_viewData.publishedDate != null) _viewData.publishedDate,
            ].join(' · '),
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
              letterSpacing: 0.15,
            ),
          ),
        ),
      ],
    );
  }

  // ── DOI ──
  Widget _buildDoiRow(ColorScheme colorScheme, TextTheme textTheme) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(
          ClipboardData(text: 'https://doi.org/${_viewData.article.doi}'),
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('DOI 链接已复制')));
      },
      child: Row(
        children: [
          Icon(Icons.link_rounded, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _viewData.article.doi,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
                decoration: TextDecoration.underline,
                decorationColor: colorScheme.primary.withValues(alpha: 0.4),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── 标签区域 ──
  Widget _buildTags(ColorScheme colorScheme, TextTheme textTheme) {
    final mainTag = _viewData.displayMaintag;
    final subTags = _viewData.displaySubtags;

    if (mainTag == null && (subTags == null || subTags.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        // 主标签
        if (mainTag != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              mainTag,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        // 子标签
        if (subTags != null)
          ...subTags.map(
            (tag) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                tag,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOneStanceSummary(
    ColorScheme colorScheme,
    TextTheme textTheme,
    AppSetting settings,
  ) {
    if (_viewData.displayOneStanceSum == null ||
        _viewData.displayOneStanceSum!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _viewData.displayOneStanceSum!,
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface,
              fontSize: settings.contentFontSize.toDouble(),
              fontWeight: FontWeight.w600,
              height: 1.6,
            ),
          ),
        ),
      ),
    );
  }

  // ── 文本段落 ──
  Widget _buildSection(
    String title,
    String content,
    ColorScheme colorScheme,
    TextTheme textTheme,
    AppSetting settings,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: settings.headerBold
                  ? FontWeight.w800
                  : FontWeight.w400,
              fontSize: settings.headerFontSize.toDouble(),
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: settings.contentFontSize.toDouble(),
              height: 1.75,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  // ── 创新点列表 ──
  Widget _buildInnovations(
    ColorScheme colorScheme,
    TextTheme textTheme,
    AppSetting settings,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '创新点',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: settings.headerBold
                  ? FontWeight.w800
                  : FontWeight.w400,
              fontSize: settings.headerFontSize.toDouble(),
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          ..._viewData.displayInnovations!.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: settings.contentFontSize.toDouble(),
                        height: 1.65,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 图形摘要 ──
  Widget _buildGraphicalAbstract(
    ColorScheme colorScheme,
    TextTheme textTheme,
    AppSetting settings,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '图形摘要',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: settings.headerBold
                  ? FontWeight.w800
                  : FontWeight.w400,
              fontSize: settings.headerFontSize.toDouble(),
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CachedArticleImage(
              articleId: _viewData.article.articleId,
              imageUrl: _viewData.graphicalAbsUrl!,
              cachePath: _viewData.graphicalAbsCachePath,
              fit: BoxFit.contain,
              width: double.infinity,
            ),
          ),
        ],
      ),
    );
  }

  // ── 底部功能栏 ──
  Widget _buildBottomBar(ColorScheme colorScheme, TextTheme textTheme) {
    final hasPrev = _currentPosition > 0;
    final hasNext = _currentPosition < _articleIds.length - 1;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                tooltip: '上一篇',
                onPressed: hasPrev
                    ? () => _navigateToPosition(_currentPosition - 1)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                tooltip: '下一篇',
                onPressed: hasNext
                    ? () => _navigateToPosition(_currentPosition + 1)
                    : null,
              ),
              const Spacer(),
              Text(
                '${_currentPosition + 1} / ${_articleIds.length}',
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              // 收藏
              IconButton(
                icon: Icon(
                  _isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_outline_rounded,
                ),
                color: _isFavorite ? colorScheme.error : null,
                tooltip: _isFavorite ? '取消收藏' : '收藏',
                onPressed: _toggleFavorite,
              ),

              // 分享
              IconButton(
                icon: const Icon(Icons.share_rounded),
                tooltip: '分享',
                onPressed: _shareDoi,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ArticleNotFoundPage extends StatelessWidget {
  final String? message;

  const ArticleNotFoundPage({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      appBar: AppBar(title: const Text('文章不存在')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.find_in_page_outlined,
                  size: 72,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 20),
                Text('未找到该文章', style: textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  message ?? '该文章可能已被删除、尚未同步，或当前链接无效。',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => context.go('/home/feed'),
                  icon: const Icon(Icons.home_rounded),
                  label: const Text('返回首页'),
                ),
                if (canPop) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('返回上一页'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
