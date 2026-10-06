import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n.dart';
import '../platform/platform_utils.dart';

/// The four destinations the Miuix bottom bar exposes.
///
/// Deliberately the *same* icons and the *same* labels as the Material branch in
/// `app_bottom_nav_bar.dart` — both read the same ARB keys. `test/widget_test.dart`
/// and `test/search_screen_test.dart` locate tabs with `find.byIcon`, so a drift
/// here would silently break tests that are not about the glass bar at all.
List<({IconData icon, String label})> _destinationsOf(AppLocalizations l) {
  return <({IconData icon, String label})>[
    (icon: Icons.search, label: l.navSearch),
    (icon: Icons.explore, label: l.navDiscover),
    (icon: Icons.library_music, label: l.navLibrary),
    (icon: Icons.download, label: l.navDownloads),
  ];
}

/// The floating glass bottom bar for `UiStyle.miuix`.
///
/// Wraps `liquid_glass_widgets`' [GlassTabBar.bottom] — the iOS 26
/// `UITabBarController` equivalent — in the Miuix geometry.
///
/// ## Why [GlassTabBar.bottom] and not a hand-rolled container
///
/// `GlassBottomBar` / `GlassSearchableBottomBar` were **deleted in 1.0.0**;
/// [GlassTabBar.bottom] is the replacement and is what `GlassScaffold` itself
/// hosts. It already owns the three things that are genuinely hard to get
/// right by hand:
///
/// * one shared glass layer for the whole track (the pill renders as
///   `AdaptiveLiquidGlassLayer` + `AdaptiveGlass.grouped`, so the four tabs are
///   *not* four independent backdrop reads — see 硬约束 3, "不嵌套
///   BackdropFilter"),
/// * the spring-physics sliding indicator with its jelly clip, and
/// * a `Row` of `Expanded` tab cells, which is what makes every hit target as
///   wide as its cell rather than as wide as the 28 dp glyph (硬约束 9).
///
/// The one thing it does *not* do is reserve its own height: it returns a bare
/// `Stack`, so it has to be given a height here (see [minBarHeight]).
///
/// ## Degraded (opaque) path
///
/// 硬约束 6 requires Windows to degrade. `liquid_glass_widgets` 1.7.2 caps
/// Windows at [GlassQuality.standard] *only* when
/// `LiquidGlassWidgets.wrap(adaptiveQuality: true)` installs a
/// `GlassAdaptiveScope` — and even then `standard` still runs a fragment
/// shader. The package has **no** "turn the backdrop off" switch, so the
/// opaque fallback is implemented here: a solid surface colour, a 1 dp stroke
/// and a light shadow, with no shader and no `BackdropFilter` in the tree.
///
/// The decision is [effectiveUseGlass], overridable for tests via
/// [FloatingGlassNavBar.glassOverride]. Defaulting to "not on Windows" also
/// means the widget test suite — which runs with `defaultTargetPlatform ==
/// TargetPlatform.windows` — exercises the degraded path deterministically
/// instead of depending on a GPU that is not there.
class FloatingGlassNavBar extends StatelessWidget {
  /// Height of the capsule, safe-area inset and outer margins excluded.
  ///
  /// 52 dp is the Miuix minimum from the measured spec; it is raised by the
  /// ambient text scale so a scaled-up label is never ellipsised (硬约束 9 /
  /// 可访问性). At 52 dp the cell is also ≥ 48 dp tall, satisfying the
  /// minimum touch target on its own.
  static const double minBarHeight = 52;

  /// Outer margin on the left and right screen edges.
  static const double sideMargin = 36;

  /// Padding between the capsule's edge and the first/last tab cell, and the
  /// gap between two adjacent tab cells. [GlassTabBar.bottom] takes the first
  /// as `horizontalPadding` and the second as `spacing`.
  static const double innerPadding = 12;

  /// Glyph size.
  static const double iconSize = 28;

  /// Label font size at text scale 1.0.
  static const double labelFontSize = 11;

  /// Capsule corner radius — constant, never interpolated (硬约束 7).
  ///
  /// 50 dp is a *shape specifier*, not a literal corner: the capsule is 52 dp
  /// tall, so Flutter's `RRect` clamps the radius to `height / 2 == 26` and the
  /// surface reads as a true stadium. Keeping the specifier constant means the
  /// shape stays a capsule at every height the text scaler can produce, which
  /// is exactly what interpolating the radius linearly would break.
  static const double barRadius = 50;

  /// Clearance between the capsule and the screen's bottom edge when the
  /// platform has no gesture/navigation inset to respect.
  static const double bottomMargin = 36;

  /// Clearance when the platform *does* reserve a bottom view inset (Android
  /// gesture/navigation bar), added on top of that inset.
  static const double androidBottomMargin = 26;

  /// Key on the glass branch, so tests can assert that the glass surface is
  /// present without depending on package internals.
  static const Key glassKey = Key('floating-glass-nav-bar-glass');

  /// Key on the opaque/degraded branch.
  static const Key opaqueKey = Key('floating-glass-nav-bar-opaque');

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// Test seam. `null` (the default) auto-detects: glass everywhere except
  /// Windows, which always takes the opaque path (硬约束 6).
  final bool? glassOverride;

  const FloatingGlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.glassOverride,
  });

  /// Whether the glass surface is used for the given platform.
  static bool useGlassFor(AppPlatform platform) =>
      platform != AppPlatform.windows;

  bool get effectiveUseGlass =>
      glassOverride ?? useGlassFor(PlatformUtils.current);

  /// The capsule's own height at the ambient text scale, safe-area inset and
  /// outer margin excluded.
  ///
  /// This mirrors the `height` computed in [build] (`minBarHeight` grown by
  /// `textScaler`, clamped to 2.0). Use it when a widget must sit *flush on top
  /// of* the capsule: reserving [obstructionHeight] instead would also reserve
  /// the decorative [bottomMargin], which nothing occupies, leaving a visible
  /// gap between the capsule and whatever sits above it.
  static double barHeight(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 2.0);
    return minBarHeight * scale;
  }

  /// Total space the bar occupies at the bottom of a page, safe-area inset
  /// included. Used when content must clear the whole capsule *including* its
  /// bottom margin.
  static double obstructionHeight(BuildContext context) {
    return barHeight(context) +
        bottomMargin +
        MediaQuery.viewPaddingOf(context).bottom;
  }

  @override
  Widget build(BuildContext context) {
    // 硬约束 10: read the two MediaQuery facets actually needed instead of
    // `MediaQuery.of`, which would subscribe this bar to inset / orientation
    // changes it does not care about.
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final hasBottomInset = MediaQuery.viewPaddingOf(context).bottom > 0;

    // Grow the capsule with the text scale so the single-line label always
    // fits — the glass path renders labels with `maxLines: 1`, so a fixed
    // height would truncate rather than overflow.
    final scale = textScale.clamp(1.0, 2.0);
    final height = minBarHeight * scale;
    final icon = iconSize * scale;
    final radius = barRadius;

    final resolvedBottomMargin = hasBottomInset
        ? (defaultTargetPlatform == TargetPlatform.android
              ? androidBottomMargin
              : 0.0)
        : bottomMargin;

    return Padding(
      padding: EdgeInsets.only(
        left: sideMargin,
        right: sideMargin,
        bottom: resolvedBottomMargin,
      ),
      child: effectiveUseGlass
          ? _buildGlassBar(
              context,
              height: height,
              icon: icon,
              radius: radius,
            )
          : _buildOpaqueBar(
              context,
              height: height,
              icon: icon,
              radius: radius,
            ),
    );
  }

  // ── Glass branch ──────────────────────────────────────────────────────────

  Widget _buildGlassBar(
    BuildContext context, {
    required double height,
    required double icon,
    required double radius,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final destinations = _destinationsOf(context.l10n);

    return SizedBox(
      key: glassKey,
      height: height,
      child: GlassTabBar.bottom(
        // The public constructors assert `selectedIndex` is in range; a stale
        // index from a hot-reload or a shorter destination list would crash the
        // whole shell, so clamp instead of trusting the caller.
        selectedIndex: selectedIndex.clamp(0, destinations.length - 1),
        onTabSelected: onDestinationSelected,
        tabs: [
          for (final destination in destinations)
            GlassTab(
              icon: Icon(destination.icon),
              label: destination.label,
            ),
        ],
        // 硬约束 (task-4 交付物 4): pass quality explicitly. Keeping the
        // parameter null would let `resolveQuality` fall back to `premium` for
        // this widget class, and an explicit value also has to clear the
        // `GlassAdaptiveScope` ceiling — so pinning it here is deliberate.
        //
        // ⚠️ COUPLING — do not change these two to `GlassQuality.minimal`
        // without updating the tests. At `standard` the package renders through
        // `LightweightLiquidGlass`, which pushes a raw `BackdropFilterLayer`
        // (not the `BackdropFilter` widget). At `minimal` it switches to
        // `_FrostedFallback`, which DOES use a real `BackdropFilter` widget, so
        // these two assertions would start failing:
        //   - test/app_bottom_nav_bar_test.dart:80  (findsNothing)
        //   - test/floating_glass_nav_bar_test.dart:311 (findsNothing)
        // The failure would look like a nav-bar regression even though the
        // cause is the quality enum, so the relationship is recorded here.
        quality: GlassQuality.standard,
        backgroundQuality: GlassQuality.standard,
        barHeight: height,
        barBorderRadius: radius,
        iconSize: icon,
        labelFontSize: labelFontSize,
        horizontalPadding: innerPadding,
        verticalPadding: 0,
        spacing: innerPadding,
        tabPadding: EdgeInsets.zero,
        // The four localised labels are the destinations; a glow disc per tab
        // adds colour noise the Miuix chrome does not use.
        selectedIconColor: colorScheme.onSecondaryContainer,
        unselectedIconColor: colorScheme.onSurfaceVariant,
        indicatorColor: colorScheme.secondaryContainer,
      ),
    );
  }

  // ── Opaque / degraded branch ──────────────────────────────────────────────

  /// No shader, no `BackdropFilter`: a solid surface, a 1 dp stroke and a light
  /// shadow. Everything that makes the glass branch expensive is absent here on
  /// purpose — this is the path Windows (and any platform whose shader support
  /// is in doubt) actually renders.
  Widget _buildOpaqueBar(
    BuildContext context, {
    required double height,
    required double icon,
    required double radius,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final destinations = _destinationsOf(context.l10n);

    // The key — and therefore the measured bounds — goes on this SizedBox, not
    // on the Container: `Container(clipBehavior:)` inserts a `ClipPath`, and
    // the nearest render object under the Container's element is that clip,
    // whose bounds are the *parent's*, not the capsule's.
    return SizedBox(
      key: opaqueKey,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(radius),
          // 1 dp stroke, solid — no glow.
          border: Border.all(
            color: colorScheme.outlineVariant,
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 12,
              spreadRadius: 0,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: innerPadding),
            child: Row(
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Expanded(
                    child: _OpaqueDestination(
                      destination: destinations[i],
                      selected: i == selectedIndex,
                      iconSize: icon,
                      onTap: () => onDestinationSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single destination cell on the opaque path.
///
/// `Expanded` gives it the full cell width and [Row] gives it the full bar
/// height, so the gesture surface is the whole cell — comfortably past the
/// 48 dp minimum even though the glyph is 28 dp.
class _OpaqueDestination extends StatelessWidget {
  final ({IconData icon, String label}) destination;
  final bool selected;
  final double iconSize;
  final VoidCallback onTap;

  const _OpaqueDestination({
    required this.destination,
    required this.selected,
    required this.iconSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      // The icon and the label below would otherwise be merged into this node
      // and announce the destination twice ("搜索\n搜索"). Excluding them keeps
      // exactly one node carrying exactly one label.
      excludeSemantics: true,
      // `Expanded` only makes the cell's *width* tight — the row lays its
      // children out with loose height — so without this the tap target would
      // shrink to the 28dp glyph plus its label instead of filling the bar.
      child: SizedBox(
        height: double.infinity,
        child: GestureDetector(
          // Opaque so the whole cell answers the tap, not just the painted
          // glyph or the 2dp gap between the two.
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                destination.icon,
                size: iconSize,
                color: foreground,
              ),
              const SizedBox(height: 2),
              Text(
                destination.label,
                textAlign: TextAlign.center,
                // No maxLines / no ellipsis: the bar's height grows with the
                // text scale so the label always has room to render in full
                // (可访问性要求 — 不得截断).
                style: TextStyle(
                  fontSize: FloatingGlassNavBar.labelFontSize,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
