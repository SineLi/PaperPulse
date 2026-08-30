import 'package:flutter/material.dart';

/// A subtle separator that indicates where the user last stopped reading.
///
/// The marker is presentation-only; callers decide where it belongs in an
/// article feed and whether it should be shown.
class LastReadMarker extends StatelessWidget {
  const LastReadMarker({super.key, this.label = '上次阅读到这'});

  /// Text displayed in the center of the marker.
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(child: Divider(color: colorScheme.outlineVariant)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(child: Divider(color: colorScheme.outlineVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
