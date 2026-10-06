import 'package:flutter/material.dart';

import '../../models/platform_type.dart';

/// Platform brand accent and icon, defined once.
///
/// Seven screens used to carry their own near-identical `switch (platform)`
/// (discovery, recommendations, rankings, likes, history, login, settings) and
/// they had already drifted: `local` rendered as `Colors.grey` in three of them
/// and as `colorScheme.primary` in four.
///
/// Those two `local` treatments are kept as two named entry points instead of
/// being silently unified — which one a screen wants is a visual decision, not
/// something to change while extracting a helper. Unifying them deliberately is
/// a UI task (see the accessibility/theming workstream).
class PlatformAccent {
  const PlatformAccent._();

  /// 网易云音乐 red.
  static const Color netease = Color(0xFFE60026);

  /// QQ音乐 green.
  static const Color qq = Color(0xFF31C27C);

  /// 酷狗音乐 blue.
  static const Color kugou = Color(0xFF2CA2F9);

  /// Brand accent for [platform]. Local files follow the theme, because they
  /// belong to the user rather than to a service.
  static Color colorOf(BuildContext context, PlatformType platform) =>
      switch (platform) {
        PlatformType.local => Theme.of(context).colorScheme.primary,
        PlatformType.netease => netease,
        PlatformType.qq => qq,
        PlatformType.kugou => kugou,
      };

  /// Accent for a badge or tile where local content should read as deliberately
  /// neutral instead of branded.
  ///
  /// Takes no [BuildContext] precisely because this variant never consults the
  /// theme — which is what lets the library lists and the settings account rows
  /// (plain `ConsumerWidget`/`StatelessWidget` helpers) call it directly.
  static Color neutralColorOf(PlatformType platform) => switch (platform) {
    PlatformType.local => Colors.grey,
    PlatformType.netease => netease,
    PlatformType.qq => qq,
    PlatformType.kugou => kugou,
  };

  /// Icon for [platform], matching the settings account rows.
  static IconData iconOf(PlatformType platform) => switch (platform) {
    PlatformType.local => Icons.folder_open,
    PlatformType.netease => Icons.cloud_outlined,
    PlatformType.qq => Icons.music_note,
    PlatformType.kugou => Icons.headphones,
  };
}
