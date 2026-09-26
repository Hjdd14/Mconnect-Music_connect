import 'package:flutter/animation.dart';

/// Central motion vocabulary for the app.
///
/// Every duration, curve, offset and scale used by a shared transition lives
/// here, so the router and the individual widgets keep referencing one source
/// of truth instead of scattering magic numbers
/// (see docs/mconnect-improvement-plan.md, 阶段 A / E-16).
abstract final class AppMotion {
  /// Forward duration of the secondary-page route transition.
  ///
  /// Locked by `test/widget_test.dart` (`app router gives normal pages a
  /// readable transition pace`); do not change it without updating that test.
  static const Duration routeForward = Duration(milliseconds: 280);

  /// Reverse (pop) duration of the secondary-page route transition.
  ///
  /// Locked by `test/widget_test.dart`; shorter than [routeForward] on purpose
  /// so returning to the previous page feels immediate.
  static const Duration routeReverse = Duration(milliseconds: 220);

  /// Curve applied while a page enters.
  static const Curve routeCurve = Curves.easeOutCubic;

  /// Horizontal entry offset of the incoming page, as a fraction of its width.
  ///
  /// The incoming page slides in **fully opaque** and covers the page below; the
  /// page underneath is not animated at all. This is deliberate, not an oversight:
  /// the route backing's opacity is what the user sees over their background image
  /// and has to stay low (especially on the home screen), so the transition cannot
  /// rely on that backing to hide the outgoing page — an opaque incoming page makes
  /// the masking structural instead of arithmetic.
  ///
  /// The constants that used to drive the outgoing page (`outgoingSlide`,
  /// `outgoingFade`, `depthScale`) and the incoming fade were removed with it, so
  /// no dead motion vocabulary is left behind suggesting they still apply.
  static const double incomingSlide = 0.06;

  /// Duration used by tab indicator animations (阶段 B).
  static const Duration tabIndicator = Duration(milliseconds: 200);

  /// Duration used when switching bottom navigation destinations (阶段 C).
  static const Duration navBarSwitch = Duration(milliseconds: 300);
}
