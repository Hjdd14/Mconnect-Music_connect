import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
///
/// ## [insetChild] and why a Navigator must not be inset here
///
/// The bottom clearance used to be applied to whatever `child` was — including
/// `AppRouteShell`'s nested `Navigator`. That created a band **no route can paint
/// into**: the nested `Navigator`'s `Overlay` sits inside this `Padding`, and
/// `_RenderTheater.paint` clips to its own bounds
/// (`packages/flutter/lib/src/widgets/overlay.dart`, `pushClipRect`). A routed
/// page therefore stops at `H − inset` and can never cover the bottom 144 dp.
///
/// Something has to cover it, and the only thing outside the nested navigator
/// that can is the *root shell page* — whose backing is gated on the current
/// location. So the patch appeared and vanished the instant a navigation started,
/// while the page that was sliding away kept its own frosted sheet for another
/// 220 ms: the screen showed a **sharp band under a frosted page**, briefly, in
/// both directions.
///
/// The fix is to stop punching the hole: `AppRouteShell` passes `insetChild:
/// false`, so the nested navigator fills the screen, and each routed page
/// reserves the clearance *inside itself* instead ([RouteBottomInset]). One
/// mechanism, and the sheet that frosts the page now frosts the whole screen
/// with it.
///
/// Keep the default `true` for a stack that hosts page content directly — that
/// is what `HomeScreen` does when no `ShellRoute` is above it.
class MiuixBottomStack extends StatelessWidget {
  /// The page content. Receives bottom padding sized to the capsules in play, so
  /// it is never covered.
  final Widget child;

  /// Whether this stack reserves the bottom clearance for [child] itself.
  ///
  /// `true` (the default) is right when [child] *is* the page content, as in
  /// `HomeScreen`'s standalone shape. `AppRouteShell` passes `false`: its child is
  /// a nested `Navigator`, and a `Padding` around one hides the bottom of the
  /// screen from every route inside it — see the class doc.
  final bool insetChild;

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
    this.insetChild = true,
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
          child: insetChild
              ? Padding(
                  padding: EdgeInsets.only(bottom: inset),
                  child: child,
                )
              // A nested `Navigator` (see [insetChild]): it must be able to paint
              // to the bottom edge, so the clearance moves into each route.
              : child,
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

/// Reserves the floating bottom stack's clearance **inside a route**.
///
/// This is the counterpart to `MiuixBottomStack(insetChild: false)`. Once the
/// nested `Navigator` is allowed to fill the screen — so a routed page can paint a
/// frosted sheet across the whole of it — the clearance has to be applied per
/// route instead, and it has to sit *below* the sheet in the tree so the sheet
/// still covers the bottom edge.
///
/// The effective constraints are identical to the old `Padding` around the
/// navigator: the page's widget is laid out in `(W, H − inset)` with its top-left
/// at the screen's top-left either way. Only *where* the hole is punched changes —
/// and that is the whole point, because a hole around a `Navigator` is a hole no
/// route can paint into.
///
/// It reads the UI style itself rather than taking it as a parameter, so every
/// route gets one definition of the clearance.
class RouteBottomInset extends ConsumerWidget {
  final Widget child;

  const RouteBottomInset({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(uiStyleProvider).style;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MiuixBottomLayout.contentInsetFor(
          context,
          style,
          hasNavBar: false,
        ),
      ),
      child: child,
    );
  }
}
