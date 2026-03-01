import 'package:flutter/material.dart';

import '../data/models/journal.dart';
import '../data/models/journal_filter.dart';
import 'journal_card.dart';
import 'journal_filter_sheet.dart';
import 'unified_list_page.dart';

/// 加载期刊的回调：返回指定分页与筛选条件的期刊列表
typedef JournalLoader =
    Future<List<Journal>> Function(int limit, int offset, JournalFilter filter);

/// 搜索期刊的回调
typedef JournalSearcher =
    Future<List<Journal>> Function(String query, int limit, int offset);

/// 期刊列表页：基于 [UnifiedListPage] 的便捷封装，
/// 内置 JournalCard、筛选底部弹窗和期刊骨架屏。
class JournalListPage extends StatefulWidget {
  final String title;
  final List<Widget>? actions;
  final JournalLoader loadJournals;
  final JournalSearcher? searchJournals;
  final bool Function(int journalId) isFollowed;
  final Future<void> Function(Journal journal, bool follow)? onFollowChanged;
  final VoidCallback? onSettings;
  final Future<List<String>> Function()? loadFilterPublishers;
  final Future<List<String>> Function()? loadFilterCasCategories;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;
  final int pageSize;
  final ScrollController? scrollController;

  const JournalListPage({
    super.key,
    required this.title,
    required this.loadJournals,
    required this.isFollowed,
    this.searchJournals,
    this.onFollowChanged,
    this.actions,
    this.onSettings,
    this.loadFilterPublishers,
    this.loadFilterCasCategories,
    this.emptyIcon = Icons.book_outlined,
    this.emptyTitle = '暂无期刊',
    this.emptySubtitle = '期刊数据加载中…',
    this.pageSize = 30,
    this.scrollController,
  });

  @override
  State<JournalListPage> createState() => _JournalListPageState();
}

class _JournalListPageState extends State<JournalListPage> {
  JournalFilter _filter = JournalFilter.empty;

  // 懒加载缓存
  List<String>? _cachedPublishers;
  List<String>? _cachedCasCategories;

  Future<void> _openFilterSheet() async {
    // 第一次打开时并行拉取出版商 & CAS 分区
    if (_cachedPublishers == null || _cachedCasCategories == null) {
      final results = await Future.wait([
        widget.loadFilterPublishers?.call() ?? Future.value(<String>[]),
        widget.loadFilterCasCategories?.call() ?? Future.value(<String>[]),
      ]);
      _cachedPublishers = results[0];
      _cachedCasCategories = results[1];
    }

    if (!mounted) return;

    final result = await showJournalFilterSheet(
      context,
      current: _filter,
      publishers: _cachedPublishers!,
      casCategories: _cachedCasCategories!,
    );

    if (result != null && result != _filter) {
      setState(() => _filter = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return UnifiedListPage<Journal>(
      key: ValueKey(_filter),
      title: widget.title,
      actions: widget.actions,
      loadItems: (limit, offset) => widget.loadJournals(limit, offset, _filter),
      searchItems: widget.searchJournals,
      searchHint: '搜索期刊名称、缩写、出版商…',
      onFilter: _openFilterSheet,
      filterActive: _filter.isActive,
      onSettings: widget.onSettings,
      emptyIcon: widget.emptyIcon,
      emptyTitle: widget.emptyTitle,
      emptySubtitle: widget.emptySubtitle,
      pageSize: widget.pageSize,
      scrollController: widget.scrollController,
      skeletonCount: 8,
      skeletonBuilder: (cs) => _JournalSkeletonCard(colorScheme: cs),
      itemBuilder: (ctx, journal, index, _1, _2) {
        return JournalCard(
          journal: journal,
          isFollowed: widget.isFollowed(journal.journalId),
          onFollowChanged: widget.onFollowChanged == null
              ? null
              : (follow) async {
                  await widget.onFollowChanged!(journal, follow);
                },
        );
      },
    );
  }
}

// ── 期刊骨架卡片 ──
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
            CircleAvatar(radius: 22, backgroundColor: bone),
            const SizedBox(width: 14),
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
