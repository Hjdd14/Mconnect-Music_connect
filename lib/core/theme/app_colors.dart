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
