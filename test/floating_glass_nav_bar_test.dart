import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mconnect/app.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/core/theme/app_background_provider.dart';
import 'package:mconnect/core/theme/ui_style_provider.dart';
import 'package:mconnect/core/widgets/floating_glass_nav_bar.dart';

/// The exact icon/label pairing the Material branch uses. Pinned here as data
/// so a drift in the Miuix bar is caught by this test rather than by an
/// unrelated screen test that happens to `find.byIcon`.
const _destinations = <({IconData icon, String label})>[
  (icon: Icons.search, label: '搜索'),
  (icon: Icons.explore, label: '发现'),
  (icon: Icons.library_music, label: '音乐库'),
  (icon: Icons.download, label: '下载'),
];

void main() {
  // `PlatformUtils` is process-global: leaving an override behind would leak
  // the platform into every later test in the same file (and, with -j 1, into
  // later files).
  tearDown(() => PlatformUtils.setDebugOverride(null));

  Widget host(Widget child, {TextScaler textScaler = TextScaler.noScaling}) {
    // The real shell hands the bar *loose* bottom-anchored constraints:
    // `home_screen.dart` drops it into `Positioned(left: 0, right: 0, bottom:
    // 0)` inside a `Stack`, so only the width is tight and the bar supplies its
    // own height. A tight-height parent (e.g. a bare `Align`) would clamp the
    // bar's height away — `BoxConstraints.enforce` can only shrink, never
    // loosen — and the test would measure something the app never builds.
    return MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: Stack(
            children: [
              Positioned(left: 0, right: 0, bottom: 0, child: child),
            ],
          ),
        ),
      ),
    );
  }

  group('structure', () {
    testWidgets('renders the four destinations with the Material pairing', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          FloatingGlassNavBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            glassOverride: false,
          ),
        ),
      );

      for (final destination in _destinations) {
        expect(
          find.byIcon(destination.icon),
          findsOneWidget,
          reason: 'missing icon ${destination.icon}',
        );
        expect(
          find.text(destination.label),
          findsOneWidget,
          reason: 'missing label ${destination.label}',
        );
      }
    });

    testWidgets('every destination announces itself as a selectable button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        host(
          FloatingGlassNavBar(
            selectedIndex: 2,
            onDestinationSelected: (_) {},
            glassOverride: false,
          ),
        ),
      );

      for (final destination in _destinations) {
        final node = tester.getSemantics(
          find.bySemanticsLabel(destination.label),
        );
        expect(
          node.flagsCollection.isButton,
          isTrue,
          reason: '${destination.label} is not exposed as a button',
        );
      }

      // Must be disposed inside the body: `addTearDown` runs *after*
      // `_endOfTestVerifications`, which asserts that no handle is still live.
      handle.dispose();
    });

    testWidgets('the selected destination is the one marked selected', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        host(
          FloatingGlassNavBar(
            selectedIndex: 3,
            onDestinationSelected: (_) {},
            glassOverride: false,
          ),
        ),
      );

      final selected = tester.getSemantics(
        find.bySemanticsLabel('下载'),
      );
      expect(selected.flagsCollection.isSelected, Tristate.isTrue);

      final unselected = tester.getSemantics(
        find.bySemanticsLabel('搜索'),
      );
      expect(unselected.flagsCollection.isSelected, Tristate.isFalse);

      handle.dispose();
    });

    testWidgets('swapping selectedIndex only re-colours the glyphs', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          FloatingGlassNavBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            glassOverride: false,
          ),
        ),
      );
      final firstColor = tester
          .widget<Icon>(find.byIcon(Icons.search))
          .color;

      await tester.pumpWidget(
        host(
          FloatingGlassNavBar(
            selectedIndex: 1,
            onDestinationSelected: (_) {},
            glassOverride: false,
          ),
        ),
      );

      expect(
        tester.widget<Icon>(find.byIcon(Icons.search)).color,
        isNot(firstColor),
      );
      expect(
        tester.widget<Icon>(find.byIcon(Icons.explore)).color,
        firstColor,
      );
    });

    testWidgets('every destination cell is at least a 48dp touch target', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          FloatingGlassNavBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            glassOverride: false,
          ),
        ),
      );

      // The glyphs are 28dp; the target has to come from the cell, so measure
      // the padded cell rather than the icon.
      final barSize = tester.getSize(find.byKey(FloatingGlassNavBar.opaqueKey));
      expect(
        barSize.height,
        greaterThanOrEqualTo(48),
        reason: 'capsule is shorter than the 48dp minimum touch target',
      );

      final tapTargets = find.descendant(
        of: find.byKey(FloatingGlassNavBar.opaqueKey),
        matching: find.byType(GestureDetector),
      );
      expect(tapTargets, findsNWidgets(_destinations.length));
      for (var i = 0; i < _destinations.length; i++) {
        final size = tester.getSize(tapTargets.at(i));
        expect(
          size.height,
          greaterThanOrEqualTo(48),
          reason: 'cell $i is only ${size.height}dp tall',
        );
        expect(
          size.width,
          greaterThanOrEqualTo(48),
          reason: 'cell $i is only ${size.width}dp wide',
        );
      }
    });

    testWidgets('a scaled-up label is neither truncated nor clipped', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          FloatingGlassNavBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            glassOverride: false,
          ),
          textScaler: const TextScaler.linear(2),
        ),
      );

      // The capsule's height is what buys the room; a fixed height would have
      // left the label to be ellipsised or clipped.
      final barSize = tester.getSize(find.byKey(FloatingGlassNavBar.opaqueKey));
      expect(barSize.height, FloatingGlassNavBar.minBarHeight * 2);

      for (final destination in _destinations) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(destination.label),
        );
        // The widget never asks for truncation in the first place...
        expect(paragraph.maxLines, isNull);
        expect(paragraph.overflow, TextOverflow.clip);

        // ...and the label really was painted in full: what the paragraph laid
        // out is what the same text needs on an unconstrained line, so nothing
        // was ellipsised into a narrower box.
        final painter = TextPainter(
          text: paragraph.text,
          textDirection: TextDirection.ltr,
          textScaler: const TextScaler.linear(2),
        )..layout();
        expect(
          paragraph.size.width,
          greaterThanOrEqualTo(painter.width - 0.5),
          reason: '${destination.label} was ellipsised',
        );
        expect(
          paragraph.size.height,
          greaterThanOrEqualTo(painter.height - 0.5),
          reason: '${destination.label} was vertically clipped',
        );
      }
    });
  });

  group('destination callbacks', () {
    for (var i = 0; i < _destinations.length; i++) {
      testWidgets('tapping ${_destinations[i].label} reports index $i', (
        tester,
      ) async {
        final tapped = <int>[];

        await tester.pumpWidget(
          host(
            FloatingGlassNavBar(
              selectedIndex: 0,
              onDestinationSelected: tapped.add,
              glassOverride: false,
            ),
          ),
        );

        await tester.tap(find.byIcon(_destinations[i].icon));
        await tester.pumpAndSettle();

        expect(tapped, [i]);
      });
    }
  });

  group('degraded (opaque) path', () {
    testWidgets('Windows never builds a shader or backdrop surface', (
      tester,
    ) async {
      PlatformUtils.setDebugOverride(AppPlatform.windows);

      await tester.pumpWidget(
        host(
          FloatingGlassNavBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(FloatingGlassNavBar.opaqueKey), findsOneWidget);
      expect(find.byKey(FloatingGlassNavBar.glassKey), findsNothing);
      expect(find.byType(GlassTabBar), findsNothing);
      // These three are the whole cost of the glass path: a backdrop read, a
      // filtered layer, or the package's shader-backed surface.
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byType(AdaptiveGlass), findsNothing);
      expect(find.byType(AdaptiveLiquidGlassLayer), findsNothing);
      expect(find.byType(LightweightLiquidGlass), findsNothing);
    });

    testWidgets('the opaque surface still draws a surface, stroke and shadow', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          FloatingGlassNavBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            glassOverride: false,
          ),
        ),
      );

      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(FloatingGlassNavBar.opaqueKey),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      final decoration = box.decoration as BoxDecoration;

      expect(decoration.color, isNotNull);
      expect(decoration.border, isNotNull);
      expect((decoration.border! as Border).top.width, 1);
      expect(decoration.boxShadow, isNotEmpty);
      // Radius is a constant shape specifier, never interpolated.
      expect(
        (decoration.borderRadius! as BorderRadius).topLeft.x,
        FloatingGlassNavBar.barRadius,
      );
    });

    testWidgets('the surface colour is opaque', (tester) async {
      await tester.pumpWidget(
        host(
          FloatingGlassNavBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            glassOverride: false,
          ),
        ),
      );

      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(FloatingGlassNavBar.opaqueKey),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      final color = (box.decoration as BoxDecoration).color!;
      expect(color.a, 1.0);
    });

    test('only Windows is excluded from the glass path', () {
      expect(FloatingGlassNavBar.useGlassFor(AppPlatform.windows), isFalse);
      for (final platform in const [
        AppPlatform.android,
        AppPlatform.ios,
        AppPlatform.macos,
        AppPlatform.linux,
      ]) {
        expect(
          FloatingGlassNavBar.useGlassFor(platform),
          isTrue,
          reason: '$platform should use the glass surface',
        );
      }
    });
  });

  group('glass path', () {
    testWidgets('a non-Windows platform builds GlassTabBar.bottom', (
      tester,
    ) async {
      PlatformUtils.setDebugOverride(AppPlatform.android);

      await tester.pumpWidget(
        host(
          FloatingGlassNavBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(FloatingGlassNavBar.glassKey), findsOneWidget);
      expect(find.byKey(FloatingGlassNavBar.opaqueKey), findsNothing);

      // The 1.0.0 replacement for the deleted `GlassBottomBar`. Asserting the
      // concrete type is what pins "no pre-1.0 API" here.
      expect(find.byType(GlassTabBar), findsOneWidget);
    });

    testWidgets('the glass bar renders the same four destinations', (
      tester,
    ) async {
      PlatformUtils.setDebugOverride(AppPlatform.android);

      await tester.pumpWidget(
        host(
          FloatingGlassNavBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
      );
      await tester.pump();

      // `GlassTabBar.bottom` paints its tabs through two layers — the base row
      // and a magnified "magic lens" overlay that the jelly clip reveals — so
      // an unselected tab's glyph appears twice while the selected tab's
      // appears once. The finder counts therefore depend on `selectedIndex`;
      // pinning a number here would be asserting package internals. What must
      // not drift is *which* icons and labels are present.
      for (final destination in _destinations) {
        expect(
          find.byIcon(destination.icon),
          findsAtLeastNWidgets(1),
          reason: 'missing icon ${destination.icon}',
        );
        expect(
          find.text(destination.label),
          findsAtLeastNWidgets(1),
          reason: 'missing label ${destination.label}',
        );
      }

      final tabs = tester.widget<GlassTabBar>(find.byType(GlassTabBar)).tabs;
      expect(
        tabs
            .map(
              (tab) => (
                icon: ((tab.icon! as Icon).icon),
                label: tab.label,
              ),
            )
            .toList(),
        _destinations
            .map((d) => (icon: d.icon, label: d.label))
            .toList(),
      );
    });

    testWidgets('the geometry matches the measured Miuix spec', (tester) async {
      PlatformUtils.setDebugOverride(AppPlatform.android);

      await tester.pumpWidget(
        host(
          FloatingGlassNavBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
      );
      await tester.pump();

      final bar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
      expect(bar.barHeight, FloatingGlassNavBar.minBarHeight);
      expect(bar.barBorderRadius, FloatingGlassNavBar.barRadius);
      expect(bar.iconSize, FloatingGlassNavBar.iconSize);
      expect(bar.horizontalPadding, FloatingGlassNavBar.innerPadding);
      expect(bar.spacing, FloatingGlassNavBar.innerPadding);
      expect(bar.tabs, hasLength(4));

      // 硬约束 (交付物 4): quality is passed explicitly. Leaving it null would
      // let `resolveQuality` fall back to the widget class default `premium`.
      expect(bar.quality, GlassQuality.standard);
      expect(bar.backgroundQuality, GlassQuality.standard);
    });

    testWidgets('glassOverride wins over the platform probe', (tester) async {
      PlatformUtils.setDebugOverride(AppPlatform.windows);

      await tester.pumpWidget(
        host(
          FloatingGlassNavBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            glassOverride: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(FloatingGlassNavBar.glassKey), findsOneWidget);

      // ...and the other way round, so the override is a genuine two-way seam.
      await tester.pumpWidget(
        host(
          FloatingGlassNavBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            glassOverride: false,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(FloatingGlassNavBar.opaqueKey), findsOneWidget);
    });

    testWidgets('side margins and bottom clearance match the spec', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          FloatingGlassNavBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            glassOverride: false,
          ),
        ),
      );

      final screenWidth = tester.getSize(find.byType(MaterialApp)).width;
      final barRect = tester.getRect(
        find.byKey(FloatingGlassNavBar.opaqueKey),
      );

      expect(barRect.left, FloatingGlassNavBar.sideMargin);
      expect(
        screenWidth - barRect.right,
        FloatingGlassNavBar.sideMargin,
      );
      expect(
        tester.getSize(find.byType(Scaffold)).height - barRect.bottom,
        FloatingGlassNavBar.bottomMargin,
      );
    });

    testWidgets('a stale selectedIndex is clamped instead of asserted', (
      tester,
    ) async {
      PlatformUtils.setDebugOverride(AppPlatform.android);

      await tester.pumpWidget(
        host(
          FloatingGlassNavBar(
            selectedIndex: 99,
            onDestinationSelected: (_) {},
          ),
        ),
      );
      await tester.pump();

      // GlassTabBar.bottom asserts `selectedIndex < tabs.length`; the clamp is
      // what keeps a stale index from taking the whole shell down.
      expect(
        tester.widget<GlassTabBar>(find.byType(GlassTabBar)).selectedIndex,
        3,
      );
    });
  });

  group('app shell glass scopes', () {
    // `MconnectApp.buildGlassShell` is the exact function `MaterialApp.router`'s
    // `builder` calls. Invoking it directly keeps the assertion about the glass
    // infrastructure instead of about Hive, media_kit and the auth session
    // restore, all of which pumping the whole app would drag in.
    Widget shell(UiStyle style) {
      final container = ProviderContainer(
        overrides: [
          appBackgroundSettingsProvider.overrideWith(
            (ref) => _NoBackgroundNotifier(),
          ),
        ],
      );
      addTearDown(container.dispose);

      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => MconnectApp.buildGlassShell(
              context,
              const SizedBox(key: Key('routed-content')),
              style,
            ),
          ),
        ),
      );
    }

    testWidgets('UiStyle.material adds no glass wrapper (invariant I-8)', (
      tester,
    ) async {
      await tester.pumpWidget(shell(UiStyle.material));

      expect(find.byKey(glassMaterialAncestorKey), findsNothing);
      expect(find.byType(GlassAdaptiveScope), findsNothing);
      // ...but the shell content is still built, and no *extra* full-screen
      // Material plate was introduced.
      expect(find.byKey(const Key('routed-content')), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const Key('routed-content')),
          matching: find.byType(Material),
        ),
        findsNothing,
      );
    });

    testWidgets('UiStyle.miuix installs the glass scope behind a Material', (
      tester,
    ) async {
      await tester.pumpWidget(shell(UiStyle.miuix));

      expect(find.byType(GlassAdaptiveScope), findsOneWidget);
      expect(find.byKey(glassMaterialAncestorKey), findsOneWidget);
      expect(find.byKey(const Key('routed-content')), findsOneWidget);

      // The injected Material is the transparency bridge the package needs; a
      // default (`canvas`) Material would paint an opaque plate over the
      // background shell.
      expect(
        tester
            .widget<Material>(find.byKey(glassMaterialAncestorKey))
            .type,
        MaterialType.transparency,
      );
      // It must be an *ancestor* of the routed content, not a sibling.
      expect(
        find.ancestor(
          of: find.byKey(const Key('routed-content')),
          matching: find.byKey(glassMaterialAncestorKey),
        ),
        findsOneWidget,
      );
    });
  });
}

class _NoBackgroundNotifier extends AppBackgroundSettingsNotifier {
  _NoBackgroundNotifier() {
    state = const AppBackgroundSettings();
  }
}
