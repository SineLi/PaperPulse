import 'package:flutter/material.dart';
import '../data/models/article_filter.dart';

/// 文章筛选底部弹窗
///
/// 使用方式：
/// ```dart
/// final result = await showArticleFilterSheet(context, current: _filter);
/// if (result != null) setState(() => _filter = result);
/// ```
Future<ArticleFilter?> showArticleFilterSheet(
  BuildContext context, {
  required ArticleFilter current,
  List<({int id, String name, String abbr})> journals = const [],
  List<String> tags = const [],
}) {
  return showModalBottomSheet<ArticleFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) =>
        _ArticleFilterSheet(initial: current, journals: journals, tags: tags),
  );
}

class _ArticleFilterSheet extends StatefulWidget {
  final ArticleFilter initial;
  final List<({int id, String name, String abbr})> journals;
  final List<String> tags;

  const _ArticleFilterSheet({
    required this.initial,
    required this.journals,
    required this.tags,
  });

  @override
  State<_ArticleFilterSheet> createState() => _ArticleFilterSheetState();
}

class _ArticleFilterSheetState extends State<_ArticleFilterSheet> {
  late ReadStatusFilter _readStatus;
  late Set<int> _selectedJournalIds;
  late Set<String> _selectedTags;
  late SortOrder _sortOrder;

  @override
  void initState() {
    super.initState();
    _readStatus = widget.initial.readStatus;
    _selectedJournalIds = Set.of(widget.initial.journalIds);
    _selectedTags = Set.of(widget.initial.tags);
    _sortOrder = widget.initial.sortOrder;
  }

  bool get _isActive =>
      _readStatus != ReadStatusFilter.all ||
      _selectedJournalIds.isNotEmpty ||
      _selectedTags.isNotEmpty ||
      _sortOrder != SortOrder.byId;

  void _reset() {
    setState(() {
      _readStatus = ReadStatusFilter.all;
      _selectedJournalIds = {};
      _selectedTags = {};
      _sortOrder = SortOrder.byId;
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      ArticleFilter(
        readStatus: _readStatus,
        journalIds: _selectedJournalIds,
        tags: _selectedTags,
        sortOrder: _sortOrder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) {
        return Column(
          children: [
            _buildHandle(cs),
            _buildHeader(cs, tt),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                children: [
                  // ── 排序方式 ──
                  _buildSectionTitle('排序方式', tt, cs),
                  const SizedBox(height: 10),
                  _buildSortChips(cs, tt),

                  const SizedBox(height: 24),

                  // ── 阅读状态 ──
                  _buildSectionTitle('阅读状态', tt, cs),
                  const SizedBox(height: 10),
                  _buildReadStatusChips(cs, tt),

                  const SizedBox(height: 24),

                  // ── 期刊 ──
                  _buildSectionTitle('期刊', tt, cs),
                  const SizedBox(height: 10),
                  _buildJournalChips(cs, tt),

                  const SizedBox(height: 24),

                  // ── 话题标签 ──
                  _buildSectionTitle('话题标签', tt, cs),
                  const SizedBox(height: 10),
                  _buildTagChips(cs, tt),

                  const SizedBox(height: 24),
                ],
              ),
            ),
            _buildApplyButton(cs, tt),
          ],
        );
      },
    );
  }

  // ── 顶部拖动把手 ──
  Widget _buildHandle(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: cs.onSurfaceVariant.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  // ── 标题栏 ──
  Widget _buildHeader(ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 12),
      child: Row(
        children: [
          Text(
            '筛选',
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          if (_isActive)
            TextButton(
              onPressed: _reset,
              child: Text('重置', style: TextStyle(color: cs.primary)),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: '关闭',
          ),
        ],
      ),
    );
  }

  // ── 分区标题 ──
  Widget _buildSectionTitle(String title, TextTheme tt, ColorScheme cs) {
    return Text(
      title,
      style: tt.labelLarge?.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  // ── 排序方式 Chips ──
  Widget _buildSortChips(ColorScheme cs, TextTheme tt) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: SortOrder.values.map((order) {
        final selected = _sortOrder == order;
        return FilterChip(
          label: Text(order.label),
          tooltip: order.description,
          selected: selected,
          onSelected: (_) => setState(() => _sortOrder = order),
          showCheckmark: true,
          avatar: selected
              ? null
              : Icon(
                  order == SortOrder.byId
                      ? Icons.rss_feed_outlined
                      : Icons.calendar_today_outlined,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
          labelStyle: tt.labelMedium?.copyWith(
            color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
          selectedColor: cs.secondaryContainer,
          backgroundColor: cs.surfaceContainerHighest,
          // side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        );
      }).toList(),
    );
  }

  // ── 阅读状态 Chips ──
  Widget _buildReadStatusChips(ColorScheme cs, TextTheme tt) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ReadStatusFilter.values.map((status) {
        final selected = _readStatus == status;
        return FilterChip(
          label: Text(status.label),
          selected: selected,
          onSelected: (_) => setState(() => _readStatus = status),
          showCheckmark: true,
          labelStyle: tt.labelMedium?.copyWith(
            color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
          selectedColor: cs.secondaryContainer,
          backgroundColor: cs.surfaceContainerHighest,
          // side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        );
      }).toList(),
    );
  }

  // ── 期刊 Chips ──
  Widget _buildJournalChips(ColorScheme cs, TextTheme tt) {
    if (widget.journals.isEmpty) {
      return _buildEmptyHint('暂无期刊数据', cs, tt);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.journals.map((j) {
        final selected = _selectedJournalIds.contains(j.id);
        return FilterChip(
          label: Text(j.abbr.isNotEmpty ? j.abbr : j.name),
          selected: selected,
          onSelected: (_) => setState(() {
            if (selected) {
              _selectedJournalIds.remove(j.id);
            } else {
              _selectedJournalIds.add(j.id);
            }
          }),
          showCheckmark: selected,
          labelStyle: tt.labelMedium?.copyWith(
            color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
          selectedColor: cs.secondaryContainer,
          backgroundColor: cs.surfaceContainerHighest,
          // side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        );
      }).toList(),
    );
  }

  // ── 话题标签 Chips ──
  Widget _buildTagChips(ColorScheme cs, TextTheme tt) {
    if (widget.tags.isEmpty) {
      return _buildEmptyHint('暂无标签数据', cs, tt);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.tags.map((tag) {
        final selected = _selectedTags.contains(tag);
        return FilterChip(
          label: Text(tag),
          selected: selected,
          onSelected: (_) => setState(() {
            if (selected) {
              _selectedTags.remove(tag);
            } else {
              _selectedTags.add(tag);
            }
          }),
          showCheckmark: selected,
          labelStyle: tt.labelMedium?.copyWith(
            color: selected ? cs.onTertiaryContainer : cs.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
          selectedColor: cs.tertiaryContainer,
          backgroundColor: cs.surfaceContainerHighest,
          // side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        );
      }).toList(),
    );
  }

  // ── 空状态提示 ──
  Widget _buildEmptyHint(String text, ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }

  // ── 应用按钮 ──
  Widget _buildApplyButton(ColorScheme cs, TextTheme tt) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _apply,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              _isActive ? '应用' : '确定',
              style: tt.labelLarge?.copyWith(
                color: cs.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
