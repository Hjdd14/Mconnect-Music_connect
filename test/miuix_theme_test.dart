import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/theme/app_theme.dart';
import 'package:mconnect/core/theme/miuix_theme.dart';
import 'package:mconnect/core/widgets/app_bottom_nav_bar.dart';

/// Extracts the corner radius of a shape so the assertions can state the
/// numeric Miuix spec instead of restating the implementation.
double _cornerRadius(ShapeBorder? shape) {
  expect(shape, isA<RoundedRectangleBorder>());
  final border = shape! as RoundedRectangleBorder;
  final radius = border.borderRadius;
  expect(radius, isA<BorderRadius>());
  final resolved = radius as BorderRadius;
  // All Miuix shapes are uniform; assert that so a lopsided shape cannot slip.
  expect(resolved.topLeft, resolved.topRight);
  expect(resolved.topLeft, resolved.bottomLeft);
  return resolved.topLeft.x;
}

void main() {
  const seed = Color(0xFFE91E63);

  group('miuixTheme overrides the Miuix shape specs', () {
    final theme = miuixTheme(brightness: Brightness.light, seedColor: seed);

    test('cards are flat with the Miuix card radius', () {
      expect(theme.cardTheme.elevation, 0);
      expect(_cornerRadius(theme.cardTheme.shape), miuixCardRadius);
    });

    test('list tiles use the Miuix tile radius', () {
      expect(_cornerRadius(theme.listTileTheme.shape), miuixTileRadius);
      expect(theme.listTileTheme.contentPadding, isNotNull);
    });

    test('dialogs use the larger Miuix dialog radius', () {
      expect(_cornerRadius(theme.dialogTheme.shape), miuixDialogRadius);
    });

    test('bottom sheets are Miuix-rounded and carry a drag handle', () {
      final border = theme.bottomSheetTheme.shape! as RoundedRectangleBorder;
      final radius = border.borderRadius as BorderRadius;
      expect(radius.topLeft.x, miuixSheetRadius);
      expect(radius.bottomLeft, Radius.zero);
      expect(theme.bottomSheetTheme.showDragHandle, isTrue);
    });

    test('buttons share the tile radius and the Miuix minimum height', () {
      for (final style in [
        theme.filledButtonTheme.style,
        theme.elevatedButtonTheme.style,
        theme.outlinedButtonTheme.style,
        theme.textButtonTheme.style,
      ]) {
        expect(style, isNotNull);
        final size = style!.minimumSize?.resolve(<WidgetState>{});
        expect(size?.height, miuixButtonMinHeight);
        expect(_cornerRadius(style.shape?.resolve(<WidgetState>{})), miuixTileRadius);
      }
    });

    test('but themes are pills', () {
      final chipShape = theme.chipTheme.shape;
      expect(chipShape, isA<StadiumBorder>());
      final segmented = theme.segmentedButtonTheme.style!.shape?.resolve(
        <WidgetState>{},
      );
      expect(segmented, isA<StadiumBorder>());
    });

    test('the tab indicator is a rounded pill and the divider is gone', () {
      final indicator = theme.tabBarTheme.indicator;
      expect(indicator, isA<BoxDecoration>());
      final radius = (indicator! as BoxDecoration).borderRadius;
      expect(radius, BorderRadius.circular(miuixTabIndicatorRadius));
      expect(theme.tabBarTheme.dividerColor, Colors.transparent);
    });

    test('the switch is outline-driven when off and filled when on', () {
      final switchTheme = theme.switchTheme;
      final scheme = theme.colorScheme;

      expect(
        switchTheme.trackOutlineColor!.resolve(<WidgetState>{}),
        scheme.outline,
      );
      expect(
        switchTheme.trackOutlineColor!.resolve(
          <WidgetState>{WidgetState.selected},
        ),
        Colors.transparent,
      );
      expect(
        switchTheme.trackColor!.resolve(<WidgetState>{WidgetState.selected}),
        scheme.primary,
      );
      expect(
        switchTheme.trackOutlineWidth!.resolve(<WidgetState>{}),
        1.5,
      );
    });

    test('snackbars float with the tile radius', () {
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(_cornerRadius(theme.snackBarTheme.shape), miuixTileRadius);
    });
  });

  group('the bottom bar never cuts the background off', () {
    // The app's scaffold background is transparent on purpose, so what shows
    // through the window (the launcher wallpaper or a custom background image) is
    // the real background. An opaque `NavigationBar` cut it off in a rectangle --
    // the "背景被切成一块" the user reported. Both styles must leave it see-through.
    for (final entry in {
      'light': AppTheme.light(seedColor: seed),
      'dark': AppTheme.dark(seedColor: seed),
    }.entries) {
      test('AppTheme.${entry.key} navigation bar is fully transparent', () {
        final barTheme = entry.value.navigationBarTheme;
        expect(barTheme.backgroundColor, Colors.transparent);
        // Material 3 tints surfaces by elevation; a non-transparent tint would
        // re-introduce a translucent fill even with a transparent colour.
        expect(barTheme.surfaceTintColor, Colors.transparent);
      });
    }

    test('the Miuix theme inherits the transparent bar', () {
      final miuix = miuixTheme(brightness: Brightness.dark, seedColor: seed);
      expect(miuix.navigationBarTheme.backgroundColor, Colors.transparent);
      expect(miuix.navigationBarTheme.surfaceTintColor, Colors.transparent);
    });

    testWidgets('the rendered NavigationBar paints no opaque fill', (
      tester,
    ) async {
      // Assert against the app's real bar rather than a hand-built one, so this
      // covers whatever the app actually paints.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(seedColor: seed),
            home: Scaffold(
              body: AppBottomNavBar(
                selectedIndex: 0,
                onDestinationSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // What the widget resolves, not just the theme slot: a widget-level
      // `backgroundColor` default could otherwise override the theme.
      final rendered = tester.widget<NavigationBar>(find.byType(NavigationBar));
      final resolvedBackground = rendered.backgroundColor ??
          Theme.of(tester.element(find.byType(NavigationBar)))
              .navigationBarTheme
              .backgroundColor;
      expect(
        resolvedBackground?.a,
        0.0,
        reason: 'an opaque bar would cut the background off in a rectangle',
      );
      expect(
        Theme.of(tester.element(find.byType(NavigationBar)))
            .navigationBarTheme
            .surfaceTintColor
            ?.a,
        0.0,
      );
    });
  });

  group('Material path is untouched (I-8)', () {
    test('AppTheme keeps its own card shape, not the Miuix one', () {
      final material = AppTheme.light(seedColor: seed);
      final miuix = miuixTheme(brightness: Brightness.light, seedColor: seed);

      // The two themes must not be interchangeable: if someone routes the
      // Material path through miuixTheme this fails.
      expect(
        _cornerRadius(material.cardTheme.shape),
        isNot(miuixCardRadius),
      );
      expect(_cornerRadius(miuix.cardTheme.shape), miuixCardRadius);
    });

    test('AppTheme is unaffected by the presence of miuixTheme', () {
      final before = AppTheme.light(seedColor: seed);
      miuixTheme(brightness: Brightness.light, seedColor: seed);
      final after = AppTheme.light(seedColor: seed);

      expect(_cornerRadius(after.cardTheme.shape), _cornerRadius(before.cardTheme.shape));
      expect(after.colorScheme.primary, before.colorScheme.primary);
    });

    test('importing the dark variant also honours brightness', () {
      final dark = miuixTheme(brightness: Brightness.dark, seedColor: seed);
      expect(dark.brightness, Brightness.dark);
      expect(_cornerRadius(dark.cardTheme.shape), miuixCardRadius);
    });
  });
}
