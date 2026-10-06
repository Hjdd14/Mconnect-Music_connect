import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../theme/ui_style_provider.dart';
import 'floating_glass_nav_bar.dart';

/// Bottom navigation chrome for the home shell.
///
/// Dispatches on [uiStyleProvider]:
/// * [UiStyle.material] renders the exact `NavigationBar` that used to be
///   inlined in `home_screen.dart` — same widget, same four destinations, same
///   icons and labels — so the Material path stays pixel-identical.
/// * [UiStyle.miuix] renders [FloatingGlassNavBar], the floating liquid-glass
///   capsule backed by `liquid_glass_widgets` (阶段 C).
class AppBottomNavBar extends ConsumerWidget {
  /// Present only on the [UiStyle.miuix] floating capsule.
  ///
  /// The Material branch intentionally carries no key so that it stays
  /// reconcilable as the exact widget `home_screen.dart` used to build.
  static const Key miuixKey = Key('app-bottom-nav-bar-miuix');

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  // The floating geometry lives on `FloatingGlassNavBar` (the capsule) and
  // `MiuixBottomLayout` (how the capsules stack). Forwarding copies used to live
  // here (`floatingObstructionHeight`, `floatingBarInset`, `floatingBarHeight`,
  // `floatingBottomMargin`); they went stale as soon as the page inset moved to
  // `MiuixBottomLayout`, so they were removed rather than kept as aliases.

  const AppBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(uiStyleProvider).style;
    switch (style) {
      case UiStyle.material:
        return _buildMaterial(context);
      case UiStyle.miuix:
        return _buildMiuix();
    }
  }

  Widget _buildMaterial(BuildContext context) {
    // Deliberately no `key`: this must stay the same widget the home screen
    // used to build inline, so element reconciliation is unchanged too.
    final l = context.l10n;
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      // Same ARB keys as the Miuix branch (loating_glass_nav_bar.dart), so
      // switching UI style cannot change the four labels.
      destinations: [
        NavigationDestination(icon: const Icon(Icons.search), label: l.navSearch),
        NavigationDestination(icon: const Icon(Icons.explore), label: l.navDiscover),
        NavigationDestination(
          icon: const Icon(Icons.library_music),
          label: l.navLibrary,
        ),
        NavigationDestination(icon: const Icon(Icons.download), label: l.navDownloads),
      ],
    );
  }

  /// The safe area is applied *inside* the bar, never around it.
  ///
  /// `home_screen.dart` drops this widget into a `Positioned(left: 0, right: 0,
  /// bottom: 0)`, which gives it unbounded height. A `SafeArea` on the outside
  /// would therefore consume the whole screen instead of measuring the capsule
  /// (measured 800x600 instead of 800x72), and the floating bar would land in
  /// the wrong place.
  Widget _buildMiuix() {
    return SafeArea(
      key: miuixKey,
      top: false,
      child: FloatingGlassNavBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
      ),
    );
  }
}
