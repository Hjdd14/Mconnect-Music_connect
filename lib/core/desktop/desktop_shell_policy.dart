import 'dart:io';

import '../platform/platform_utils.dart';

/// Whether this process should render the desktop shell instead of the mobile
/// navigation shell.
///
/// The decision is deliberately made **once at startup**, not from a widget
/// width: resizing a desktop window must not turn the app back into the phone
/// layout. Inside the desktop shell the layout still adapts to width (collapsed
/// sidebar, hidden right panel, compact player bar).
///
/// Tests run on a Windows host, so [PlatformUtils.isDesktop] is true there too.
/// Without the `FLUTTER_TEST` guard every existing widget test would suddenly
/// render the desktop chrome and the mobile regression suite would stop
/// protecting the phone UI. Tests that *want* the desktop shell set
/// [debugOverride] before building the router.
abstract final class DesktopShellPolicy {
  DesktopShellPolicy._();

  /// Test seam. `null` means "decide from the platform".
  static bool? debugOverride;

  static bool get isEnabled {
    final override = debugOverride;
    if (override != null) return override;
    if (!PlatformUtils.isDesktop) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return true;
  }

  /// Width at or above which the right panel is docked instead of overlaid.
  static const double wideBreakpoint = 1440;

  /// Width at or above which the right panel is available and the sidebar is
  /// expanded.
  // Three columns need ~1120 logical px: 248 sidebar + content + 340 panel
  // + gaps. At 1024 the old 1000 breakpoint kept the right panel visible and
  // squeezed the content to ~400 px; hide it until there is room.
  static const double mediumBreakpoint = 1120;

  /// Width at or above which the sidebar keeps labels.
  static const double sidebarLabelBreakpoint = 900;

  static const double sidebarWidth = 248;
  static const double sidebarCollapsedWidth = 76;
  static const double nowPlayingWidth = 340;
  static const double playerBarHeight = 92;
  static const double playerBarCompactHeight = 80;
  static const double contentMaxWidth = 1400;
}
