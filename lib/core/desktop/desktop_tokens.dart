import 'package:flutter/material.dart';

/// Spacing scale for the desktop shell. One source of truth so the sidebar,
/// player bar and pages cannot drift apart by a few pixels each.
abstract final class DesktopSpacing {
  DesktopSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;
}

abstract final class DesktopRadii {
  DesktopRadii._();

  static const Radius xs = Radius.circular(6);
  static const Radius sm = Radius.circular(8);
  static const Radius md = Radius.circular(12);
  static const Radius lg = Radius.circular(16);
  static const Radius xl = Radius.circular(20);
  static const Radius pill = Radius.circular(999);

  static const BorderRadius smAll = BorderRadius.all(sm);
  static const BorderRadius mdAll = BorderRadius.all(md);
  static const BorderRadius lgAll = BorderRadius.all(lg);
  static const BorderRadius xlAll = BorderRadius.all(xl);
}

abstract final class DesktopDurations {
  DesktopDurations._();

  static const Duration hover = Duration(milliseconds: 120);
  static const Duration panel = Duration(milliseconds: 180);
  static const Duration page = Duration(milliseconds: 240);
}

/// Semantic desktop colours derived from the active Material colour scheme.
///
/// Keeping these in one place means a theme change (or a custom seed colour)
/// flows through the whole shell instead of leaving hard-coded greys behind.
abstract final class DesktopColors {
  DesktopColors._();

  static Color canvas(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.surface;
  }

  static Color surface(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.surfaceContainerLow;
  }

  static Color raised(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.surfaceContainer;
  }

  static Color overlay(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.surfaceContainerHigh;
  }

  static Color hairline(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.outlineVariant.withValues(alpha: 0.55);
  }

  static Color muted(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.onSurfaceVariant;
  }

  static Color hover(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.onSurface.withValues(alpha: 0.06);
  }

  static Color selected(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return scheme.primary.withValues(alpha: 0.12);
  }

  static Color scrim(BuildContext context) {
    return Colors.black.withValues(alpha: 0.42);
  }
}

abstract final class DesktopShadows {
  DesktopShadows._();

  static const List<BoxShadow> panel = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> floating = <BoxShadow>[
    BoxShadow(color: Color(0x33000000), blurRadius: 28, offset: Offset(0, 10)),
  ];
}

/// Desktop typography. The system font stack is used on purpose: bundling a
/// CJK font would add tens of megabytes to the installer, and Windows already
/// ships a good one. `fontFamilyFallback` is what makes mixed Chinese/Latin
/// lyric text render with the right glyphs on every machine.
abstract final class DesktopText {
  DesktopText._();

  static const String family = 'Segoe UI Variable Text';
  static const List<String> fallback = <String>[
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'Segoe UI',
    'Arial',
  ];

  static const TextStyle display = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.4,
  );

  static const TextStyle headline = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.2,
  );

  static const TextStyle title = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );
}
