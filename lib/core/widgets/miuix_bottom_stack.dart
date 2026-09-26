import 'package:flutter/material.dart';

import '../theme/ui_style_provider.dart';
import 'miuix_bottom_layout.dart';
import '../../features/player/presentation/widgets/mini_player_bar.dart';

/// The app's floating bottom layer: the mini-player capsule — painted once for
/// the whole app — plus whatever nav capsule the current route supplies.
///
/// ## Why the player lives here
///
/// The player is rendered by `AppRouteShell` at the **navigator** level, never by
/// a route page. When each page built its own copy, a push had both the outgoing
/// and the incoming page painting a capsule at the same position with different
/// animation opacities, so the two visibly stacked — the flashing the user
/// reported.
///
/// ## Why the nav bar is passed in rather than created here
///
/// The nav bar belongs to the home screen: its indicator has to follow the home
/// `PageView`, and `HomeScreen` is also mounted by routers that have no
/// `ShellRoute` at all (several tests build one). So the home screen owns the nav
/// bar and hands it here; only widgets that would otherwise be **duplicated**
/// belong at the navigator level. The nav bar is mounted exactly once either way.
///
/// ## Layout
///
/// ```text
/// [ content .......................... ] <- padded so nothing is covered
/// [ mini-player capsule ]                bottom: playerBottomInset (~96 dp)
/// [ nav capsule, when supplied ]         bottom: 0
/// ```
class MiuixBottomStack extends StatelessWidget {
  /// The page content. Receives bottom padding sized to the capsules in play, so
  /// it is never covered.
  final Widget child;

  /// The bottom navigation capsule, when the current route shows one.
  final Widget? navBar;

  /// Whether this stack should paint the mini player itself.
  ///
  /// Defaults to true. `HomeScreen` sets it to false when a `ShellRoute` above it
  /// is already painting the player — two live `MiniPlayerBar`s in one tree is
  /// exactly the duplication this refactor removed.
  final bool showPlayer;

  /// Which bottom-bar style is active.
  ///
  /// Passed in rather than read from the provider so the stack stays a pure
  /// function of its inputs, and so tests can lay out both styles without a
  /// container. The player's inset differs per style (80 + 8 under Material,
  /// 36 + 52 + 8 under Miuix).
  final UiStyle style;

  const MiuixBottomStack({
    super.key,
    required this.child,
    this.navBar,
    this.showPlayer = true,
    this.style = UiStyle.miuix,
  });

  @override
  Widget build(BuildContext context) {
    // The content must clear the player capsule, which floats above everything
    // else at the bottom. The nav bar always sits *below* the player, so it adds
    // nothing here.
    //
    // Deliberately computed for a *playing* player even when idle: keying this on
    // `currentSong != null` would make the page padding change the moment
    // playback starts, and `MiniPlayerBar` already collapses to nothing when
    // idle, so the cost is only a little slack at the bottom of a silent page.
    final inset = MiuixBottomLayout.contentInsetFor(
      context,
      style,
      hasNavBar: navBar != null,
    );

    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(bottom: inset),
            child: child,
          ),
        ),
        // PAINT ORDER MATTERS: the nav bar is added BEFORE the player so the
        // player is painted last, i.e. on top. The reverse order let an opaque nav
        // bar cover the lower part of the player — and even now that the bar is
        // transparent, `NavigationBar`'s indicator pill and label are not, so it
        // would still draw over the player wherever they overlap.
        if (navBar != null)
          Positioned(left: 0, right: 0, bottom: 0, child: navBar!),
        if (showPlayer)
          Positioned(
            left: MiuixBottomLayout.playerSideMargin,
            right: MiuixBottomLayout.playerSideMargin,
            bottom: MiuixBottomLayout.playerBottomInsetFor(context, style),
            child: const MiniPlayerBar(floating: true),
          ),
      ],
    );
  }
}
