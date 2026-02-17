import 'package:flutter/material.dart';

import '../data/models/journal.dart';
import 'journal_card.dart';

/// 加载期刊的回调：返回指定分页的期刊列表
typedef JournalLoader = Future<List<Journal>> Function(int limit, int offset);

/// 通用期刊列表页，封装了分页加载、骨架屏、空状态逻辑。
class JournalListPage extends StatefulWidget {
  /// AppBar 标题
  final String title;

  /// AppBar 右侧操作按钮
  final List<Widget>? actions;

  /// 加载期刊数据的回调
  final JournalLoader loadJournals;

  /// 判断某期刊是否已关注
  final bool Function(int journalId) isFollowed;

  /// 关注/取消关注回调
  final Future<void> Function(Journal journal, bool follow)? onFollowChanged;

  /// 空状态图标
  final IconData emptyIcon;

  /// 空状态标题
  final String emptyTitle;

  /// 空状态副标题
  final String emptySubtitle;

  /// 每页加载数量
  final int pageSize;

  const JournalListPage({
    super.key,
    required this.title,
    required this.loadJournals,
    required this.isFollowed,
    this.onFollowChanged,
    this.actions,
    this.emptyIcon = Icons.book_outlined,
    this.emptyTitle = '暂无期刊',
    this.emptySubtitle = '期刊数据加载中…',
    this.pageSize = 30,
  });

  @override
  State<JournalListPage> createState() => _JournalListPageState();
}

class _JournalListPageState extends State<JournalListPage> {
  final ScrollController _scrollController = ScrollController();
  final List<Journal> _journals = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentOffset = 0;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 300 &&
        !_isLoading &&
        _hasMore) {
      _loadMore();
    }
    return false;
  }

  Future<void> _loadMore() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final batch = await widget.loadJournals(widget.pageSize, _currentOffset);

      if (mounted) {
        setState(() {
          _currentOffset += batch.length;
          _journals.addAll(batch);
          _hasMore = batch.length == widget.pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载失败: $e')));
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: NestedScrollView(
          controller: _scrollController,
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar.large(
              title: Text(widget.title),
              actions: [
                if (widget.actions != null) ...widget.actions!,
                const SizedBox(width: 4),
              ],
            ),
          ],
          body: _buildBody(colorScheme, textTheme),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme, TextTheme textTheme) {
    // 首次加载 → 骨架屏
    if (_journals.isEmpty && _isLoading) {
      return _buildSkeletonList(colorScheme);
    }

    // 空状态
    if (_journals.isEmpty && !_isLoading) {
      return _buildEmptyState(colorScheme, textTheme);
    }

    // 期刊列表
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 88),
      itemCount: _journals.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _journals.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: colorScheme.primary,
                ),
              ),
            ),
          );
        }

        final journal = _journals[index];
        return JournalCard(
          journal: journal,
          isFollowed: widget.isFollowed(journal.journalId),
          onFollowChanged: widget.onFollowChanged == null
              ? null
              : (follow) async {
                  await widget.onFollowChanged!(journal, follow);
                  if (mounted) setState(() {});
                },
        );
      },
    );
  }

  // ── 骨架屏 ──
  Widget _buildSkeletonList(ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 88),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 8,
      itemBuilder: (context, index) =>
          _JournalSkeletonCard(colorScheme: colorScheme),
    );
  }

  // ── 空状态 ──
  Widget _buildEmptyState(ColorScheme colorScheme, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.emptyIcon,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: .5),
            ),
            const SizedBox(height: 16),
            Text(
              widget.emptyTitle,
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.emptySubtitle,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: .7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 骨架卡片 ──
class _JournalSkeletonCard extends StatelessWidget {
  final ColorScheme colorScheme;
  const _JournalSkeletonCard({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final bone = colorScheme.surfaceContainerHighest;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 圆形头像骨架
            CircleAvatar(radius: 22, backgroundColor: bone),
            const SizedBox(width: 14),
            // 名称骨架
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bone(bone, width: 160, height: 14),
                  const SizedBox(height: 6),
                  _bone(bone, width: 80, height: 10),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 按钮骨架
            _bone(bone, width: 56, height: 28, radius: 14),
          ],
        ),
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
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
