import 'package:flutter/material.dart';

import 'desktop_tokens.dart';

/// Material 3 theme for the desktop shell.
///
/// Deliberately separate from [AppTheme]: the phone theme keeps its own
/// typography, density and transparent navigation bar. Building the desktop
/// theme here means a desktop change can never silently move the phone UI.
ThemeData desktopTheme({
  required Brightness brightness,
  required Color seedColor,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  );
  final isDark = brightness == Brightness.dark;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    fontFamily: DesktopText.family,
    fontFamilyFallback: DesktopText.fallback,
    splashFactory: NoSplash.splashFactory,
  );

  final textTheme = base.textTheme.copyWith(
    displayLarge: DesktopText.display.copyWith(color: scheme.onSurface),
    headlineMedium: DesktopText.headline.copyWith(color: scheme.onSurface),
    titleMedium: DesktopText.title.copyWith(color: scheme.onSurface),
    bodyMedium: DesktopText.body.copyWith(color: scheme.onSurface),
    bodySmall: DesktopText.caption.copyWith(color: scheme.onSurfaceVariant),
    labelLarge: DesktopText.bodyStrong.copyWith(color: scheme.onSurface),
  );

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 56,
      titleTextStyle: DesktopText.title.copyWith(color: scheme.onSurface),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: DesktopRadii.lgAll),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.55),
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
    listTileTheme: ListTileThemeData(
      dense: true,
      visualDensity: VisualDensity.compact,
      shape: const RoundedRectangleBorder(borderRadius: DesktopRadii.smAll),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: DesktopSpacing.md,
        vertical: DesktopSpacing.xs,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh.withValues(alpha: 0.55),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: DesktopSpacing.md,
        vertical: DesktopSpacing.sm + 2,
      ),
      border: OutlineInputBorder(
        borderRadius: DesktopRadii.mdAll,
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: DesktopRadii.mdAll,
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: DesktopRadii.mdAll,
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
      ),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 3,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.outlineVariant.withValues(alpha: 0.5),
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.14),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      trackShape: const RoundedRectSliderTrackShape(),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.dragged);
        return scheme.onSurfaceVariant.withValues(alpha: hovered ? 0.55 : 0.28);
      }),
      thickness: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered) ? 8 : 6,
      ),
      radius: const Radius.circular(999),
      crossAxisMargin: 2,
      mainAxisMargin: 2,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 380),
      decoration: BoxDecoration(
        color: isDark ? scheme.inverseSurface : scheme.inverseSurface,
        borderRadius: DesktopRadii.smAll,
      ),
      textStyle: DesktopText.caption.copyWith(color: scheme.onInverseSurface),
      padding: const EdgeInsets.symmetric(
        horizontal: DesktopSpacing.sm,
        vertical: DesktopSpacing.xs,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: const RoundedRectangleBorder(borderRadius: DesktopRadii.mdAll),
      textStyle: DesktopText.body.copyWith(color: scheme.onSurface),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: const RoundedRectangleBorder(borderRadius: DesktopRadii.lgAll),
      titleTextStyle: DesktopText.headline.copyWith(color: scheme.onSurface),
      contentTextStyle: DesktopText.body.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: scheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: DesktopRadii.lg),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: DesktopText.body.copyWith(
        color: scheme.onInverseSurface,
      ),
      shape: const RoundedRectangleBorder(borderRadius: DesktopRadii.mdAll),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: DesktopSpacing.lg),
        shape: const RoundedRectangleBorder(borderRadius: DesktopRadii.mdAll),
        textStyle: DesktopText.bodyStrong,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: DesktopSpacing.lg),
        shape: const RoundedRectangleBorder(borderRadius: DesktopRadii.mdAll),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        textStyle: DesktopText.bodyStrong,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: DesktopSpacing.sm),
        shape: const RoundedRectangleBorder(borderRadius: DesktopRadii.smAll),
        textStyle: DesktopText.bodyStrong,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(32, 32),
        maximumSize: const Size(40, 40),
        padding: const EdgeInsets.all(DesktopSpacing.xs),
        shape: const RoundedRectangleBorder(borderRadius: DesktopRadii.smAll),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      shape: const RoundedRectangleBorder(borderRadius: DesktopRadii.smAll),
      labelStyle: DesktopText.caption.copyWith(color: scheme.onSurfaceVariant),
      padding: const EdgeInsets.symmetric(horizontal: DesktopSpacing.sm),
    ),
  );
}
