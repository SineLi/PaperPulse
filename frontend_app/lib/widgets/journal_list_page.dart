import 'package:flutter/material.dart';

import '../data/models/journal.dart';
import 'journal_card.dart';
import 'unified_list_page.dart';

/// 加载期刊的回调：返回指定分页的期刊列表
typedef JournalLoader = Future<List<Journal>> Function(int limit, int offset);

/// 搜索期刊的回调
typedef JournalSearcher =
    Future<List<Journal>> Function(String query, int limit, int offset);

/// 期刊列表页：基于 [UnifiedListPage] 的便捷封装，
/// 内置 JournalCard 和期刊骨架屏。
class JournalListPage extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final JournalLoader loadJournals;
  final JournalSearcher? searchJournals;
  final bool Function(int journalId) isFollowed;
  final Future<void> Function(Journal journal, bool follow)? onFollowChanged;
  final VoidCallback? onFilter;
  final bool filterActive;
  final VoidCallback? onSettings;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;
  final int pageSize;

  const JournalListPage({
    super.key,
    required this.title,
    required this.loadJournals,
    required this.isFollowed,
    this.searchJournals,
    this.onFollowChanged,
    this.actions,
    this.onFilter,
    this.filterActive = false,
    this.onSettings,
    this.emptyIcon = Icons.book_outlined,
    this.emptyTitle = '暂无期刊',
    this.emptySubtitle = '期刊数据加载中…',
    this.pageSize = 30,
  });

  @override
  Widget build(BuildContext context) {
    return UnifiedListPage<Journal>(
      title: title,
      actions: actions,
      loadItems: loadJournals,
      searchItems: searchJournals,
      searchHint: '搜索期刊名称、缩写、出版商…',
      onFilter: onFilter,
      filterActive: filterActive,
      onSettings: onSettings,
      emptyIcon: emptyIcon,
      emptyTitle: emptyTitle,
      emptySubtitle: emptySubtitle,
      pageSize: pageSize,
      skeletonCount: 8,
      skeletonBuilder: (cs) => _JournalSkeletonCard(colorScheme: cs),
      itemBuilder: (ctx, journal, index, _, __) {
        return JournalCard(
          journal: journal,
          isFollowed: isFollowed(journal.journalId),
          onFollowChanged: onFollowChanged == null
              ? null
              : (follow) async {
                  await onFollowChanged!(journal, follow);
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
