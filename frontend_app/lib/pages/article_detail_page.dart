import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models/article.dart';
import '../data/models/article_view_data.dart';
import '../data/db/articledb.dart';
import '../settings/settings_controller.dart';
import '../widgets/cached_image.dart';

/// 文章详情页
///
/// [articles] 当前文章列表，用于上一篇 / 下一篇导航
/// [initialIndex] 当前文章在列表中的索引
class ArticleDetailPage extends StatefulWidget {
  final List<Article> articles;
  final int initialIndex;
  final void Function(int articleId)? onArticleRead;

  const ArticleDetailPage({
    super.key,
    required this.articles,
    required this.initialIndex,
    this.onArticleRead,
  });

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  late int _currentIndex;
  late ArticleViewData _viewData;
  late ScrollController _scrollController;
  late final Map<int, ArticleViewData> _viewDataCache;
  final Set<int> _markedAsRead = <int>{};
  bool _barsVisible = true;
  double _lastScrollOffset = 0;
  late bool _isFavorite;
  bool _suppressScrollListener = false;
  bool _hasSwitchedArticle = false;

  /// 切换动画方向: 1 = 下一篇(向上滑出), -1 = 上一篇(向下滑出)
  int _slideDirection = 1;

  /// 用于 AnimatedSwitcher 的 key
  late ValueKey<int> _contentKey;

  /// 边缘过度滚动阈值（由设置 swipeSensitivity 覆盖）
  static const double _overscrollThresholdDefault = 120;

  /// 已达到阈值，等待松手后触发切换的方向: 1=下一篇, -1=上一篇, 0=无
  int _pendingDirection = 0;
  bool _showReleaseHint = false;
  bool _hapticFired = false;
  bool _pointerIsDown = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _viewDataCache = <int, ArticleViewData>{};
    _viewData = _viewDataForIndex(_currentIndex);
    _isFavorite = _viewData.isFavorite;
    _contentKey = ValueKey(_currentIndex);
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _markAsRead();
  }

  ArticleViewData _viewDataForIndex(int index) {
    return _viewDataCache.putIfAbsent(
      index,
      () => ArticleViewData.fromArticle(widget.articles[index]),
    );
  }

  void _setSwitchHint(int direction, bool visible) {
    if (_pendingDirection == direction && _showReleaseHint == visible) {
      return;
    }
    setState(() {
      _pendingDirection = direction;
      _showReleaseHint = visible;
    });
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
  bool _onScrollNotification(ScrollNotification notification) {
    final settings = context.read<SettingsController>().setting;
    final threshold = settings.swipeSensitivity <= 0
        ? _overscrollThresholdDefault
        : settings.swipeSensitivity.toDouble();

    if (notification is ScrollStartNotification) {
      _pendingDirection = 0;
      _showReleaseHint = false;
      _hapticFired = false;
    } else if (notification is ScrollUpdateNotification) {
      if (!_pointerIsDown || notification.dragDetails == null) {
        return false;
      }

      final metrics = notification.metrics;

      // 顶端越界 → 准备上一篇（受 swipeToChangeArticleUp 控制）
      if (settings.swipeToChangeArticleUp &&
          metrics.pixels < metrics.minScrollExtent &&
          _currentIndex > 0) {
        final overscroll = metrics.minScrollExtent - metrics.pixels;
        if (overscroll > threshold) {
          if (!_hapticFired) {
            _hapticFired = true;
            HapticFeedback.mediumImpact();
          }
          _setSwitchHint(-1, true);
        } else {
          _setSwitchHint(0, false);
          _hapticFired = false;
        }
      }
      // 底端越界 → 准备下一篇（受 swipeToChangeArticleDown 控制）
      else if (settings.swipeToChangeArticleDown &&
          metrics.pixels > metrics.maxScrollExtent &&
          _currentIndex < widget.articles.length - 1) {
        final overscroll = metrics.pixels - metrics.maxScrollExtent;
        if (overscroll > threshold) {
          if (!_hapticFired) {
            _hapticFired = true;
            HapticFeedback.mediumImpact();
          }
          _setSwitchHint(1, true);
        } else {
          _setSwitchHint(0, false);
          _hapticFired = false;
        }
      } else {
        _setSwitchHint(0, false);
        _hapticFired = false;
      }
    }
    return false;
  }

  void _triggerPendingSwitch() {
    _pointerIsDown = false;
    if (_showReleaseHint && _pendingDirection == -1) {
      _navigateTo(_currentIndex - 1);
    } else if (_showReleaseHint && _pendingDirection == 1) {
      _navigateTo(_currentIndex + 1);
    }
    _pendingDirection = 0;
    _showReleaseHint = false;
    _hapticFired = false;
  }

  void _navigateTo(int index) {
    if (index < 0 ||
        index >= widget.articles.length ||
        index == _currentIndex) {
      return;
    }

    if (_scrollController.hasClients && _scrollController.offset != 0) {
      _suppressScrollListener = true;
      try {
        _scrollController.jumpTo(0);
      } finally {
        _suppressScrollListener = false;
      }
    }

    setState(() {
      _hasSwitchedArticle = true;
      _slideDirection = index > _currentIndex ? 1 : -1;
      _currentIndex = index;
      _viewData = _viewDataForIndex(_currentIndex);
      _isFavorite = _viewData.isFavorite;
      _contentKey = ValueKey(_currentIndex);
      _lastScrollOffset = 0;
      _barsVisible = true;
    });
    _markAsRead();
  }

  Future<void> _markAsRead() async {
    if (_viewData.isRead || _markedAsRead.contains(_viewData.id)) return;
    _markedAsRead.add(_viewData.id);
    final db = context.read<ArticleDatabaseIO>();
    try {
      await db.setReadWithSync(_viewData.id, true);
      widget.onArticleRead?.call(_viewData.id);
    } catch (_) {
      _markedAsRead.remove(_viewData.id);
      rethrow;
    }
  }

  Future<void> _toggleFavorite() async {
    final db = context.read<ArticleDatabaseIO>();
    final newState = !_isFavorite;
    await db.setFavoriteWithSync(_viewData.id, newState);
    if (mounted) {
      setState(() => _isFavorite = newState);
    }
  }

  void _shareDoi() {
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
    final disableAnimations =
        MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;

    return PredictiveBackScope(
      child: Scaffold(
        body: Stack(
          children: [
            // ── 主要内容 ──
            Listener(
              onPointerDown: (_) => _pointerIsDown = true,
              onPointerUp: (_) => _triggerPendingSwitch(),
              onPointerCancel: (_) => _triggerPendingSwitch(),
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
                        animate: !disableAnimations && _hasSwitchedArticle,
                        child: RepaintBoundary(
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

            // ── 切换提示 ──
            Positioned(
              left: 0,
              right: 0,
              bottom: _pendingDirection == 1 ? 0 : null,
              top: _pendingDirection == -1 ? 0 : null,
              child: IgnorePointer(
                ignoring: true,
                child: SafeArea(
                  bottom: _pendingDirection == 1,
                  top: _pendingDirection == -1,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: _showReleaseHint ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 400),
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
                              _pendingDirection == -1
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: colorScheme.onInverseSurface,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _pendingDirection == -1 ? '松手切换上一篇' : '松手切换下一篇',
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

            // ── 底部功能栏 ──
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
      ),
    );
  }

  // ── 文章正文内容（独立 widget 方便做 AnimatedSwitcher） ──
  // Only animate incoming content to avoid rendering two heavy trees at once.
  Widget _buildArticleSwitchTransition({
    required Widget child,
    required bool animate,
  }) {
    if (!animate) return child;

    return TweenAnimationBuilder<double>(
      key: _contentKey,
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) {
        final translateY = (1 - value) * 50 * _slideDirection;
        final opacity = 0.82 + (0.18 * value);
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
    final hasPrev = _currentIndex > 0;
    final hasNext = _currentIndex < widget.articles.length - 1;

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
              // 上一篇
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                tooltip: '上一篇',
                onPressed: hasPrev
                    ? () => _navigateTo(_currentIndex - 1)
                    : null,
              ),

              // 下一篇
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                tooltip: '下一篇',
                onPressed: hasNext
                    ? () => _navigateTo(_currentIndex + 1)
                    : null,
              ),

              const Spacer(),

              // 位置指示
              Text(
                '${_currentIndex + 1} / ${widget.articles.length}',
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
