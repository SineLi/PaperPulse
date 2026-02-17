import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';

import '../data/models/article.dart';
import '../data/models/article_view_data.dart';
import '../data/db/articledb.dart';
import '../widgets/cached_image.dart';

/// 文章详情页
///
/// [articles] 当前文章列表，用于上一篇 / 下一篇导航
/// [initialIndex] 当前文章在列表中的索引
class ArticleDetailPage extends StatefulWidget {
  final List<Article> articles;
  final int initialIndex;

  const ArticleDetailPage({
    super.key,
    required this.articles,
    required this.initialIndex,
  });

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  late int _currentIndex;
  late ArticleViewData _viewData;
  late ScrollController _scrollController;
  bool _barsVisible = true;
  double _lastScrollOffset = 0;
  late bool _isFavorite;

  /// 切换动画方向: 1 = 下一篇(左滑), -1 = 上一篇(右滑)
  int _slideDirection = 1;

  /// 用于 AnimatedSwitcher 的 key
  late ValueKey<int> _contentKey;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _viewData = ArticleViewData.fromArticle(widget.articles[_currentIndex]);
    _isFavorite = _viewData.isFavorite;
    _contentKey = ValueKey(_currentIndex);
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _markAsRead();
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final delta = offset - _lastScrollOffset;
    if (delta > 8 && _barsVisible) {
      setState(() => _barsVisible = false);
    } else if (delta < -8 && !_barsVisible) {
      setState(() => _barsVisible = true);
    }
    _lastScrollOffset = offset;
  }

  void _navigateTo(int index) {
    if (index < 0 || index >= widget.articles.length) return;
    setState(() {
      _slideDirection = index > _currentIndex ? 1 : -1;
      _currentIndex = index;
      _viewData = ArticleViewData.fromArticle(widget.articles[_currentIndex]);
      _isFavorite = _viewData.isFavorite;
      _contentKey = ValueKey(_currentIndex);
      _scrollController.jumpTo(0);
      _lastScrollOffset = 0;
      _barsVisible = true;
    });
    _markAsRead();
  }

  Future<void> _markAsRead() async {
    final db = context.read<ArticleDatabaseIO>();
    await db.setReadWithSync(_viewData.id, true);
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

    return Scaffold(
      body: Stack(
        children: [
          // ── 主要内容 ──
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // AppBar — floating + snap，向下滚动隐藏，向上微滑即回
              SliverAppBar(
                floating: true,
                snap: true,
                title: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  // child: Text(
                  //   _viewData.displayJournalName ??
                  //       _viewData.article.journalName,
                  //   key: ValueKey('appbar_$_currentIndex'),
                  //   style: textTheme.titleMedium,
                  // ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.open_in_browser_rounded),
                    tooltip: '在浏览器中打开',
                    onPressed: _shareDoi,
                  ),
                  const SizedBox(width: 4),
                ],
              ),

              // 正文 — 带切换动画
              SliverToBoxAdapter(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    // 根据 child 的 key 判断进场方向
                    final isIncoming = child.key == _contentKey;
                    final offsetBegin = isIncoming
                        ? Offset(_slideDirection * 0.15, 0)
                        : Offset(-_slideDirection * 0.15, 0);
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: offsetBegin,
                        end: Offset.zero,
                      ).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: _buildArticleContent(
                    colorScheme,
                    textTheme,
                    key: _contentKey,
                  ),
                ),
              ),
            ],
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
    );
  }

  // ── 文章正文内容（独立 widget 方便做 AnimatedSwitcher） ──
  Widget _buildArticleContent(
    ColorScheme colorScheme,
    TextTheme textTheme, {
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
                fontWeight: FontWeight.w800,
                fontSize: 28,
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

            // ── 摘要 / 正文 ──
            if (_viewData.displaySummary != null &&
                _viewData.displaySummary!.isNotEmpty)
              _buildSection(
                '总结',
                _viewData.displaySummary!,
                colorScheme,
                textTheme,
              ),

            // ── 亮点 ──
            if (_viewData.displayHighlights != null &&
                _viewData.displayHighlights!.isNotEmpty)
              _buildSection(
                '亮点',
                _viewData.displayHighlights!,
                colorScheme,
                textTheme,
              ),

            // ── 创新点 ──
            if (_viewData.displayInnovations != null &&
                _viewData.displayInnovations!.isNotEmpty)
              _buildInnovations(colorScheme, textTheme),

            // ── 图形摘要 ──
            if (_viewData.graphicalAbsUrl != null &&
                _viewData.graphicalAbsUrl!.isNotEmpty)
              _buildGraphicalAbstract(colorScheme, textTheme),

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

  // ── 文本段落 ──
  Widget _buildSection(
    String title,
    String content,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 24,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 16,
              height: 1.75,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  // ── 创新点列表 ──
  Widget _buildInnovations(ColorScheme colorScheme, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '创新点',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 24,
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
                        fontSize: 15,
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
  Widget _buildGraphicalAbstract(ColorScheme colorScheme, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '图形摘要',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 24,
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
                icon: const Icon(Icons.navigate_before_rounded),
                tooltip: '上一篇',
                onPressed: hasPrev
                    ? () => _navigateTo(_currentIndex - 1)
                    : null,
              ),

              // 下一篇
              IconButton(
                icon: const Icon(Icons.navigate_next_rounded),
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
