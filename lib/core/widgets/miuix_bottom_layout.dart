import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/widgets.dart';

import '../theme/ui_style_provider.dart';
import 'floating_glass_nav_bar.dart';

/// Single source of truth for the Miuix floating bottom stack.
///
/// ## Why this exists
///
/// The mini player used to be positioned independently by the two route shells:
/// `home_screen.dart` placed it above the nav capsule (52 dp from the bottom)
/// while `AppRouteShell` dropped it flush to the bottom edge (0 dp). During a
/// push both shells are in the tree at once, so the mini player was painted at
/// two different heights and visibly jumped — the same class of bug as the
/// route-transition ghosting, which also came from two code paths disagreeing
/// about one widget's geometry.
///
/// Two hard-coded numbers are the defect; this class is the fix. Both shells now
/// read the same values, and the geometry cannot drift apart again.
///
/// ## Geometry (Miuix, text scale 1.0)
///
/// ```text
/// screen bottom
///   ^ navBottomMargin          36   (FloatingGlassNavBar.bottomMargin)
///   ^ nav capsule              52   (FloatingGlassNavBar.minBarHeight)
///   ^ playerGap                 8
///   ^ mini player capsule      48   (playerHeight)
///   --------------------------------
///   player bottom inset        96   = 36 + 52 + 8
///   content inset             144   = 96 + 48
/// ```
///
/// The player's inset is **independent of whether the nav capsule is visible**.
/// That is deliberate: a constant inset keeps the page's content padding — and
/// therefore the mini player itself — identical on every route, which is what
/// removes the jump. The cost is that on a route without the nav capsule the
/// player floats 96 dp above the bottom edge.
class MiuixBottomLayout {
  MiuixBottomLayout._();

  /// Height of the mini player when it is rendered as a floating capsule.
  ///
  /// Deliberately shorter than the nav capsule (52 dp) so the two read as
  /// distinct layers.
  static const double playerHeight = 48;

  /// Outer margin on the left and right of the player capsule.
  ///
  /// Smaller than [FloatingGlassNavBar.sideMargin] (36 dp) on purpose: the
  /// player capsule is meant to read as *longer* than the nav capsule.
  static const double playerSideMargin = 16;

  /// Clearance between the top of the nav capsule and the bottom of the player
  /// capsule.
  static const double playerGap = 8;

  /// Height of the nav capsule at the ambient text scale.
  static double navCapsuleHeight(BuildContext context) =>
      FloatingGlassNavBar.barHeight(context);

  /// Height of the Material bottom bar (`NavigationBar`).
  ///
  /// Matches Flutter's own default (`navigation_bar.dart` builds the bar with
  /// `height: 80.0`). It is a constant here because the player's inset has to be
  /// computable before the bar is laid out; `MaterialBottomLayout`'s own test
  /// asserts this equals the height the real widget reports, so a change in
  /// Flutter fails the test instead of silently re-introducing the overlap.
  static const double materialNavBarHeight = 80;

  /// Distance from the bottom edge of the screen to the bottom of the player
  /// capsule.
  ///
  /// Depends only on the nav capsule's own geometry, never on whether that
  /// capsule is currently mounted.
  static double playerBottomInset(BuildContext context) =>
      FloatingGlassNavBar.bottomMargin +
      navCapsuleHeight(context) +
      playerGap;

  /// The player's bottom inset for the active bottom-bar style.
  ///
  /// The two styles have genuinely different bottom geometry, and sharing one
  /// number between them was a defect: the Miuix inset (`36 + 52`) was applied
  /// under Material too, where the bar is a flush 80 dp `NavigationBar` with no
  /// outer margin — so the player sat 16 dp *inside* an opaque bar and its lower
  /// part was painted over.
  static double playerBottomInsetFor(BuildContext context, UiStyle style) =>
      style == UiStyle.material
      ? materialNavBarHeight + playerGap // 80 + 8 = 88
      : playerBottomInset(context); // 36 + 52 + 8 = 96

  /// Total distance the floating stack reaches up from the bottom edge, i.e.
  /// the inset a page must reserve so its content is never covered.
  static double contentInset(BuildContext context) =>
      playerBottomInset(context) + playerHeight;

  /// The page-content reserve for the active style.
  ///
  /// The nav bar always sits *below* the player, so it contributes nothing to
  /// this reserve; [hasNavBar] is part of the signature so call sites state which
  /// shape they are laying out, and so a future style whose bar floats over the
  /// content can account for it here rather than at every call site.
  static double contentInsetFor(
    BuildContext context,
    UiStyle style, {
    required bool hasNavBar,
  }) {
    return playerBottomInsetFor(context, style) + playerHeight;
  }

  /// Distance from the bottom edge to the bottom of the nav capsule, including
  /// the device's bottom safe-area inset.
  ///
  /// Mirrors the padding `FloatingGlassNavBar.build` applies to itself.
  static double navBottomInset(BuildContext context) {
    final viewInset = MediaQuery.viewPaddingOf(context).bottom;
    final margin = viewInset > 0
        ? (defaultTargetPlatform == TargetPlatform.android
              ? FloatingGlassNavBar.androidBottomMargin
              : 0.0)
        : FloatingGlassNavBar.bottomMargin;
    return margin + viewInset;
  }
}
