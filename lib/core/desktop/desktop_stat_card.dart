import 'package:flutter/material.dart';

import 'desktop_tokens.dart';

/// One metric tile for a desktop dashboard page.
///
/// Deliberately not a [Card]: desktop pages sit on the shell's rounded plate, so
/// a second Material elevation reads as a card inside a card. A hairline border
/// on the panel colour is what the shell already uses for its panels.
class DesktopStatCard extends StatelessWidget {
  const DesktopStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.hint,
    this.accent,
  });

  final IconData icon;
  final String label;
  final String value;

  /// Second line under the value, e.g. "共 128 首" or a platform name.
  final String? hint;

  /// Overrides the primary tint (used to colour-code a metric).
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.all(DesktopSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.72),
        borderRadius: DesktopRadii.lgAll,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: DesktopRadii.smAll,
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(width: DesktopSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesktopText.caption.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesktopSpacing.md),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesktopText.headline.copyWith(color: scheme.onSurface),
          ),
          if (hint != null) ...[
            const SizedBox(height: DesktopSpacing.xxs),
            Text(
              hint!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesktopText.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A labelled proportional bar used by the listening-statistics page.
///
/// A [FractionallySizedBox] over a track instead of a chart package: the report
/// already carries the numbers, and a dependency for a handful of bars would be
/// a build-size change for a decoration.
class DesktopStatBar extends StatelessWidget {
  const DesktopStatBar({
    super.key,
    required this.label,
    required this.fraction,
    this.trailing,
    this.accent,
    this.labelWidth = 168,
  });

  final String label;

  /// Bar length as a 0..1 fraction of the track.
  final double fraction;

  /// The number rendered to the right of the bar.
  final String? trailing;

  final Color? accent;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;
    final clamped = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesktopSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesktopText.body.copyWith(color: scheme.onSurface),
            ),
          ),
          const SizedBox(width: DesktopSpacing.sm),
          Expanded(
            child: ClipRRect(
              borderRadius: DesktopRadii.smAll,
              child: Stack(
                children: [
                  Container(
                    height: 8,
                    color: scheme.onSurface.withValues(alpha: 0.06),
                  ),
                  FractionallySizedBox(
                    widthFactor: clamped <= 0 ? 0.001 : clamped,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.78),
                        borderRadius: DesktopRadii.smAll,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: DesktopSpacing.sm),
            SizedBox(
              width: 72,
              child: Text(
                trailing!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: DesktopText.caption.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
