import 'package:flutter/material.dart';

/// Semantic color constants that adapt to light/dark theme.
/// Use these instead of hardcoded Colors.xxx values.
class AppColors {
  AppColors._();

  // Placeholder / skeleton backgrounds
  static const placeholderLight = Color(0xFFE0E0E0);
  static const placeholderDark = Color(0xFF424242);

  // Lyrics
  static const lyricsInactiveLight = Color(0xFF9E9E9E);
  static const lyricsInactiveDark = Color(0xFF757575);

  // Download status
  static const downloadComplete = Color(0xFF4CAF50);
  static const downloadFailed = Color(0xFFEF5350);
  static const downloadPaused = Color(0xFFFFA726);

  // Platform brand colors (kept as-is, not theme-dependent)
  static const neteaseRed = Color(0xFFE60026);
  static const qqGreen = Color(0xFF31C27C);
  static const kugouBlue = Color(0xFF2CA2F9);

  // ---- Fixed composites -------------------------------------------------
  //
  // These four are deliberately *not* theme-aware: each one sits next to a
  // user-chosen or brand colour, where "follow the theme" would be wrong (a
  // dark-mode QR background stops scanning; a surface-coloured scrim tints the
  // user's wallpaper). They live here so the intent is recorded once instead of
  // `Colors.white` / `Colors.black` appearing at ten call sites with no reason
  // attached.

  /// Black base of the composited background picture: the letterbox around it and
  /// the dark-mode scrim drawn over it (see `app_background.dart`).
  static const imageBase = Color(0xFF000000);

  /// Text / icon colour on a brand-coloured (platform accent) fill.
  static const onBrand = Color(0xFFFFFFFF);

  /// Background of a generated QR code. Maximum contrast on purpose — scanners
  /// fail against a themed surface.
  static const qrBackground = Color(0xFFFFFFFF);

  /// Check mark drawn on a user-picked colour swatch, whose colour the app does
  /// not control.
  static const swatchCheck = Color(0xFFFFFFFF);

  /// Shadow under a small colour swatch (black at 12 %).
  static const swatchShadow = Color(0x1F000000);

  /// Returns a theme-aware placeholder color.
  static Color placeholder(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? placeholderDark
        : placeholderLight;
  }

  /// Returns a theme-aware inactive lyrics color.
  static Color lyricsInactive(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? lyricsInactiveDark
        : lyricsInactiveLight;
  }
}
