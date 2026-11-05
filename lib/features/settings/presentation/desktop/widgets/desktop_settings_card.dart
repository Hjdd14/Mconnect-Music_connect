import 'package:flutter/material.dart';

import '../../../../../core/desktop/desktop_tokens.dart';

/// One rounded, hairline-bordered block of settings rows on the desktop page.
///
/// Shared by the settings page and the sections it hosts (downloads today) so
/// two cards on the same screen can never drift apart in padding or radius.
class DesktopSettingsCard extends StatelessWidget {
  const DesktopSettingsCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(DesktopSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.62),
        borderRadius: DesktopRadii.lgAll,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: DesktopText.bodyStrong.copyWith(color: scheme.onSurface),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: DesktopText.caption.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: DesktopSpacing.md),
          // A transparent Material just below the tinted DecoratedBox: ListTile
          // (and every SwitchListTile, which builds one) paints its background
          // and ink splashes on the nearest Material ancestor, and a coloured
          // DecoratedBox between the two hides them -- a debug assertion in
          // recent Flutter, invisible feedback in release.
          Material(type: MaterialType.transparency, child: child),
        ],
      ),
    );
  }
}
