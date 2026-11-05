import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tabs in the right-hand "now playing" panel.
enum DesktopPanelTab {
  nowPlaying('正在播放'),
  lyrics('歌词'),
  queue('队列');

  const DesktopPanelTab(this.label);

  final String label;
}

/// Which tab the right panel shows, or null when the panel is hidden.
///
/// Kept in Riverpod rather than in the shell's State so a page (for example the
/// player bar's lyrics button, or a "查看歌词" action in a context menu) can ask
/// the shell to open a specific tab without threading callbacks through every
/// route.
final desktopPanelTabProvider = StateProvider<DesktopPanelTab?>(
  (ref) => DesktopPanelTab.nowPlaying,
);

/// User's explicit sidebar collapse preference. The effective state also
/// depends on the window width; see [DesktopShell].
final desktopSidebarCollapsedProvider = StateProvider<bool>((ref) => false);
