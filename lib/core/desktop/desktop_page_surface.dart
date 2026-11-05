import 'package:flutter/material.dart';

import 'desktop_tokens.dart';

class DesktopPageSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const DesktopPageSurface({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.82),
        borderRadius: DesktopRadii.xlAll,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.42),
        ),
        boxShadow: DesktopShadows.panel,
      ),
      // Deliberately no ClipRRect: the child is the nested Navigator, and a
      // clip here would also clip popup menus and dialogs rendered in that
      // navigator's overlay. The rounded decoration alone is enough for the
      // transparent desktop pages; legacy pages that paint an opaque square
      // corner are a Phase-2 migration item, not a reason to break popups.
      child: RepaintBoundary(
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );
  }
}
