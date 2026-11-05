import 'package:flutter/material.dart';

import 'desktop_tokens.dart';

class DesktopEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const DesktopEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(DesktopSpacing.xxxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: DesktopRadii.lgAll,
                ),
                child: Icon(icon, size: 26, color: scheme.primary),
              ),
              const SizedBox(height: DesktopSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: DesktopText.title.copyWith(color: scheme.onSurface),
              ),
              if (message != null) ...[
                const SizedBox(height: DesktopSpacing.sm),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: DesktopText.body.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: DesktopSpacing.lg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
