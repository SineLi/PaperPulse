import 'package:flutter/material.dart';
import '../data/models/journal_filter.dart';

/// 期刊筛选底部弹窗
///
/// 使用方式：
/// ```dart
/// final result = await showJournalFilterSheet(context, current: _filter);
/// if (result != null) setState(() => _filter = result);
/// ```
Future<JournalFilter?> showJournalFilterSheet(
  BuildContext context, {
  required JournalFilter current,
  List<String> publishers = const [],
  List<String> casCategories = const [],
}) {
  return showModalBottomSheet<JournalFilter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _JournalFilterSheet(
      initial: current,
      publishers: publishers,
      casCategories: casCategories,
    ),
  );
}

class _JournalFilterSheet extends StatefulWidget {
  final JournalFilter initial;
  final List<String> publishers;
  final List<String> casCategories;

  const _JournalFilterSheet({
    required this.initial,
    required this.publishers,
    required this.casCategories,
  });

  @override
  State<_JournalFilterSheet> createState() => _JournalFilterSheetState();
}

class _JournalFilterSheetState extends State<_JournalFilterSheet> {
  late double _ifMin;
  late SciFilter _sciFilter;
  late Set<String> _selectedPublishers;
  late Set<String> _selectedCasCategories;

  @override
  void initState() {
    super.initState();
    _ifMin = widget.initial.ifMin;
    _sciFilter = widget.initial.sciFilter;
    _selectedPublishers = Set.of(widget.initial.publishers);
    _selectedCasCategories = Set.of(widget.initial.casCategories);
  }

  bool get _isActive =>
      _ifMin != 0.0 ||
      _sciFilter != SciFilter.all ||
      _selectedPublishers.isNotEmpty ||
      _selectedCasCategories.isNotEmpty;

  void _reset() {
    setState(() {
      _ifMin = 0.0;
      _sciFilter = SciFilter.all;
      _selectedPublishers = {};
      _selectedCasCategories = {};
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      JournalFilter(
        ifMin: _ifMin,
        sciFilter: _sciFilter,
        publishers: _selectedPublishers,
        casCategories: _selectedCasCategories,
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
                  // ── 影响因子 ──
                  _buildSectionTitle('影响因子（IF）', tt, cs),
                  const SizedBox(height: 4),
                  _buildIfSlider(cs, tt),

                  const SizedBox(height: 24),

                  // ── SCI 收录 ──
                  _buildSectionTitle('SCI 收录', tt, cs),
                  const SizedBox(height: 10),
                  _buildSciChips(cs, tt),

                  if (widget.publishers.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    // ── 出版商 ──
                    _buildSectionTitle('出版商', tt, cs),
                    const SizedBox(height: 10),
                    _buildPublisherChips(cs, tt),
                  ],

                  if (widget.casCategories.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    // ── CAS 分区 ──
                    _buildSectionTitle('CAS 分区', tt, cs),
                    const SizedBox(height: 10),
                    _buildCasChips(cs, tt),
                  ],

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

  // ── 影响因子 Slider ──
  Widget _buildIfSlider(ColorScheme cs, TextTheme tt) {
    final label = _ifMin == 0.0 ? '不限' : '≥ ${_ifMin.toInt()}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: tt.bodyMedium?.copyWith(
                color: _ifMin == 0.0 ? cs.onSurfaceVariant : cs.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '0 – 20',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        Slider(
          value: _ifMin,
          min: 0,
          max: 20,
          divisions: 10,
          label: label,
          activeColor: cs.primary,
          inactiveColor: cs.surfaceContainerHighest,
          onChanged: (v) => setState(() => _ifMin = v),
        ),
      ],
    );
  }

  // ── SCI 收录芯片 ──
  Widget _buildSciChips(ColorScheme cs, TextTheme tt) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: SciFilter.values.map((f) {
        final selected = _sciFilter == f;
        return FilterChip(
          label: Text(f.label),
          selected: selected,
          onSelected: (_) => setState(() => _sciFilter = f),
          selectedColor: cs.primaryContainer,
          checkmarkColor: cs.onPrimaryContainer,
          labelStyle: tt.labelMedium?.copyWith(
            color: selected ? cs.onPrimaryContainer : cs.onSurface,
          ),
        );
      }).toList(),
    );
  }

  // ── 出版商芯片（多选） ──
  Widget _buildPublisherChips(ColorScheme cs, TextTheme tt) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.publishers.map((pub) {
        final selected = _selectedPublishers.contains(pub);
        return FilterChip(
          label: Text(pub),
          selected: selected,
          onSelected: (v) {
            setState(() {
              if (v) {
                _selectedPublishers.add(pub);
              } else {
                _selectedPublishers.remove(pub);
              }
            });
          },
          selectedColor: cs.secondaryContainer,
          checkmarkColor: cs.onSecondaryContainer,
          labelStyle: tt.labelMedium?.copyWith(
            color: selected ? cs.onSecondaryContainer : cs.onSurface,
          ),
        );
      }).toList(),
    );
  }

  // ── CAS 分区芯片（多选） ──
  Widget _buildCasChips(ColorScheme cs, TextTheme tt) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.casCategories.map((cat) {
        final selected = _selectedCasCategories.contains(cat);
        return FilterChip(
          label: Text(cat),
          selected: selected,
          onSelected: (v) {
            setState(() {
              if (v) {
                _selectedCasCategories.add(cat);
              } else {
                _selectedCasCategories.remove(cat);
              }
            });
          },
          selectedColor: cs.tertiaryContainer,
          checkmarkColor: cs.onTertiaryContainer,
          labelStyle: tt.labelMedium?.copyWith(
            color: selected ? cs.onTertiaryContainer : cs.onSurface,
          ),
        );
      }).toList(),
    );
  }

  // ── 应用按钮 ──
  Widget _buildApplyButton(ColorScheme cs, TextTheme tt) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _apply,
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              _isActive ? '应用筛选' : '确认',
              style: tt.titleMedium?.copyWith(
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
