import 'package:flutter/widgets.dart';

import 'app_motion.dart';

/// Builds the shared secondary-page route transition.
///
/// The incoming page **slides in fully opaque** from the right and covers the page
/// below it. The page underneath is left exactly as it is — no fade, no scale, no
/// shift.
///
/// ## Why the incoming page must be opaque
///
/// The route backing's opacity used to double as the thing that masked the page
/// below during a transition. That coupled two unrelated requirements: making the
/// user's background image readable (which wants a *transparent* backing) and
/// preventing the two pages from compositing (which wants an *opaque* one).
///
/// Fading the incoming page in re-introduced that coupling in its worst form: at
/// 50 % opacity both pages are half-visible no matter what the backing does. An
/// opaque incoming page makes the masking structural instead of arithmetic, so the
/// backing is free to be as transparent as the background needs.
///
/// Motion is preserved because the slide alone already reads as a page change.
///
/// When [reduceMotion] is true only a fade is used — and that fade still has to
/// start at 1.0 rather than 0, or the same ghosting returns in that mode.
Widget buildAppPageTransition({
  required Animation<double> animation,
  required Animation<double> secondaryAnimation,
  required Widget child,
  required bool reduceMotion,
}) {
  if (reduceMotion) {
    // No motion at all: show the page immediately. Fading in from 0 would let the
    // outgoing page show through, which is the defect the opaque slide avoids.
    return child;
  }

  final incoming = animation.drive(CurveTween(curve: AppMotion.routeCurve));

  return SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(AppMotion.incomingSlide, 0),
      end: Offset.zero,
    ).animate(incoming),
    child: child,
  );
}
