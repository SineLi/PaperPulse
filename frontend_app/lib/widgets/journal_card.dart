import 'package:flutter/material.dart';
import '../data/models/journal.dart';
import '../data/models/article_view_data.dart';

/// 期刊卡片：默认显示头像+名称+关注按钮，点击后展开详细信息。
class JournalCard extends StatefulWidget {
  final Journal journal;
  final bool isFollowed;
  final ValueChanged<bool>? onFollowChanged;

  const JournalCard({
    super.key,
    required this.journal,
    this.isFollowed = false,
    this.onFollowChanged,
  });

  @override
  State<JournalCard> createState() => _JournalCardState();
}

class _JournalCardState extends State<JournalCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  bool _followLoading = false;

  /// 从期刊名称中提取首字母（1-2 个字符）
  String get _initials {
    final name = widget.journal.name;
    if (name.isEmpty) return '?';

    // 去掉常见前缀
    String processed = name
        .replaceAll(RegExp(r'^The\s+', caseSensitive: false), '')
        .replaceAll(RegExp(r'^Journal of\s+', caseSensitive: false), '')
        .trim();

    if (processed.isEmpty) return name[0].toUpperCase();

    final words = processed.split(RegExp(r'\s+'));
    if (words.length == 1) {
      return words[0][0].toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  /// 根据出版商获取颜色（与 feed 卡片一致）
  Color get _publisherColor {
    final publisher = widget.journal.publisher ?? '';
    return tagColorMap[publisher] ?? Colors.blueGrey;
  }

  Future<void> _handleFollowTap() async {
    if (_followLoading || widget.onFollowChanged == null) return;
    setState(() => _followLoading = true);
    try {
      widget.onFollowChanged!(!widget.isFollowed);
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── 默认行：头像 + 名称 + 关注按钮 ──
                _buildHeaderRow(colorScheme, textTheme),
                // ── 展开详情 ──
                if (_expanded) ...[
                  const SizedBox(height: 12),
                  _buildDetailSection(colorScheme, textTheme),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 头部行
  Widget _buildHeaderRow(ColorScheme colorScheme, TextTheme textTheme) {
    return Row(
      children: [
        // ── 圆形头像 ──
        CircleAvatar(
          radius: 22,
          backgroundColor: _publisherColor,
          child: Text(
            _initials,
            style: textTheme.titleSmall?.copyWith(
              color: _contrastTextColor(_publisherColor),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 14),
        // ── 期刊名称 + 缩写 ──
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.journal.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              if (widget.journal.abbreviation.isNotEmpty)
                Text(
                  widget.journal.abbreviation,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: 0.2,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // ── 关注 / 已关注 按钮 ──
        _buildFollowButton(colorScheme, textTheme),
      ],
    );
  }

  /// 关注按钮
  Widget _buildFollowButton(ColorScheme colorScheme, TextTheme textTheme) {
    if (_followLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (widget.isFollowed) {
      return OutlinedButton(
        onPressed: _handleFollowTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: BorderSide(color: colorScheme.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Text(
          '已关注',
          style: textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return FilledButton.tonal(
      onPressed: _handleFollowTap,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Text(
        '关注',
        style: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 展开详情区域
  Widget _buildDetailSection(ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (widget.journal.if0 != null)
                _buildMetricChip(
                  label: 'IF',
                  value: widget.journal.if0!.toStringAsFixed(2),
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
              if (widget.journal.if5 != null)
                _buildMetricChip(
                  label: 'IF (5yr)',
                  value: widget.journal.if5!.toStringAsFixed(2),
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
              if (widget.journal.sci > 0)
                _buildMetricChip(
                  label: 'SCI',
                  value: 'Q${widget.journal.sci}',
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
              if (widget.journal.CASBase != null &&
                  widget.journal.CASBase!.isNotEmpty)
                _buildMetricChip(
                  label: '中科院基础版',
                  value: widget.journal.CASBase!,
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
              if (widget.journal.CASUp != null &&
                  widget.journal.CASUp!.isNotEmpty)
                _buildMetricChip(
                  label: '中科院升级版',
                  value: widget.journal.CASUp!,
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
              if (widget.journal.publisher != null &&
                  widget.journal.publisher!.isNotEmpty)
                _buildMetricChip(
                  label: '出版商',
                  value: widget.journal.publisher!,
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 指标 Chip
  Widget _buildMetricChip({
    required String label,
    required String value,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label  ',
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSecondaryContainer.withValues(alpha: .7),
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: textTheme.labelMedium?.copyWith(
              color: colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// 根据背景色自动选黑/白文字
  Color _contrastTextColor(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance > 0.4 ? Colors.black87 : Colors.white;
  }
}
