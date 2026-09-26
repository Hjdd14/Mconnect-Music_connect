import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' show GlassContainer;
import 'package:mconnect/app.dart';
import 'package:mconnect/core/router/app_router.dart';
import 'package:mconnect/core/theme/app_background.dart';
import 'package:mconnect/core/theme/app_background_provider.dart';
import 'package:mconnect/core/theme/ui_style_provider.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';

/// A 1x1 transparent PNG, so `File(...).existsSync()` is true and the acrylic
/// branch is actually exercised.
const _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

late File _realImageFile;
late Directory _tempDir;

class _Style extends UiStyleNotifier {
  _Style() : super(initialStyle: UiStyle.material);
}

class _Bg extends AppBackgroundSettingsNotifier {
  _Bg({String? path}) {
    state = AppBackgroundSettings(imagePath: path);
  }
}

class _Idle implements PlayerAudioController {
  @override
  bool get playing => false;
  @override
  Duration get position => Duration.zero;
  @override
  double get volume => 1.0;
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<AudioPlaybackState> get playerStateStream => const Stream.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> setUrl(String url) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> bandGains,
  }) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  setUp(() async {
    _tempDir = await Directory.systemTemp.createTemp('mconnect_acrylic_');
    _realImageFile = File('${_tempDir.path}/bg.png');
    await _realImageFile.writeAsBytes(_png);
  });

  tearDown(() async {
    if (await _tempDir.exists()) {
      await _tempDir.delete(recursive: true);
    }
  });

  group('backing opacity is per route', () {
    test('the home screen is barely dimmed; a secondary page is not dimmed', () {
      // One value for every route is what dimmed the user's background everywhere,
      // home included. The transition no longer relies on this number (the incoming
      // page is opaque), so it is free to serve readability alone.
      expect(routeBackingOpacityFor('/'), homeBackingOpacity);
      expect(homeBackingOpacity, lessThanOrEqualTo(0.15));

      for (final route in ['/settings', '/likes', '/history', '/downloads']) {
        expect(
          routeBackingOpacityFor(route),
          0,
          reason:
              'a secondary page must not flatten the background: its readability '
              'comes from the glass blur instead',
        );
      }
    });

    testWidgets('the home route really does not dim the background', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      appRouter.go('/');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            uiStyleProvider.overrideWith((ref) => _Style()),
            appBackgroundSettingsProvider.overrideWith((ref) => _Bg()),
            playerProvider.overrideWith(
              (ref) => PlayerNotifier(
                audioController: _Idle(),
                audioControllerFactory: _Idle.new,
              ),
            ),
          ],
          child: MaterialApp.router(
            builder: (context, child) =>
                MconnectApp.buildGlassShell(context, child, UiStyle.material),
            routerConfig: appRouter,
          ),
        ),
      );
      await tester.pump();

      // The plate is the shell wrapping the routed surface. Find the one that
      // carries the route backing and check how far it dims.
      final plates = tester
          .widgetList<AppBackgroundShell>(find.byType(AppBackgroundShell))
          .where((shell) => !shell.drawImage)
          .toList();
      expect(plates, isNotEmpty);
      for (final plate in plates) {
        expect(
          plate.baseOpacity,
          lessThanOrEqualTo(0.15),
          reason: 'the home screen must not dim the background',
        );
      }
    });

    testWidgets('a secondary route paints no plate at all', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      appRouter.go('/likes');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            uiStyleProvider.overrideWith((ref) => _Style()),
            appBackgroundSettingsProvider.overrideWith((ref) => _Bg()),
            playerProvider.overrideWith(
              (ref) => PlayerNotifier(
                audioController: _Idle(),
                audioControllerFactory: _Idle.new,
              ),
            ),
          ],
          child: MaterialApp.router(
            builder: (context, child) =>
                MconnectApp.buildGlassShell(context, child, UiStyle.material),
            routerConfig: appRouter,
          ),
        ),
      );
      await tester.pump();

      final plates = tester
          .widgetList<AppBackgroundShell>(find.byType(AppBackgroundShell))
          .where((shell) => !shell.drawImage)
          .toList();
      expect(plates, isNotEmpty);
      for (final plate in plates) {
        expect(
          plate.baseOpacity,
          0,
          reason:
              'the secondary page must leave the background alone; the glass sheet '
              'is what keeps the text readable',
        );
      }
    });
  });

  group('the background image is painted once', () {
    testWidgets('no route plate paints its own copy', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      appRouter.go('/');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            uiStyleProvider.overrideWith((ref) => _Style()),
            appBackgroundSettingsProvider.overrideWith((ref) => _Bg()),
            playerProvider.overrideWith(
              (ref) => PlayerNotifier(
                audioController: _Idle(),
                audioControllerFactory: _Idle.new,
              ),
            ),
          ],
          child: MaterialApp.router(
            builder: (context, child) =>
                MconnectApp.buildGlassShell(context, child, UiStyle.material),
            routerConfig: appRouter,
          ),
        ),
      );
      await tester.pump();

      final shells = tester.widgetList<AppBackgroundShell>(
        find.byType(AppBackgroundShell),
      );
      final withImage = shells.where((s) => s.drawImage).length;
      final without = shells.where((s) => !s.drawImage).length;

      expect(
        withImage,
        1,
        reason: 'exactly one layer may paint the background image',
      );
      expect(without, greaterThanOrEqualTo(1));
    });
  });

  group('the secondary sheet is acrylic, not liquid glass', () {
    test('blurs with a near-clear fill and no outline machinery', () {
      // The liquid-glass outline could not be removed through the package API: the
      // rim comes from `GlassEffect`'s own `rimThickness` / `rimSmoothing` /
      // `edgeAlphaMultiplier`, which are not fields of `LiquidGlassSettings` and are
      // not exposed by `GlassContainer` either. Zeroing `lightIntensity`,
      // `fresnelStrength` and `glowIntensity` therefore left the outline intact.
      //
      // Acrylic removes it by construction: there is no edge-drawing code at all.
      expect(AcrylicSettings.sigma, greaterThan(0));
      expect(
        AcrylicSettings.sigma,
        greaterThanOrEqualTo(12),
        reason: 'the blur is what makes the background readable',
      );
      expect(
        AcrylicSettings.fillAlpha,
        lessThanOrEqualTo(0.2),
        reason: 'a heavy fill hides the user\'s background',
      );
    });

    testWidgets('renders a BackdropFilter and no GlassContainer', (tester) async {
      // The crux of the fix: nothing that can paint a rim is in the tree.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBackgroundSettingsProvider.overrideWith(
              (ref) => _Bg(path: _realImageFile.path),
            ),
          ],
          child: const MaterialApp(
            home: SecondaryGlassSurface(child: Text('page')),
          ),
        ),
      );

      expect(find.text('page'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsWidgets);
      expect(
        find.byType(GlassContainer),
        findsNothing,
        reason: 'a GlassContainer here would paint the rim again',
      );

      final blur = tester.widget<BackdropFilter>(
        find.ancestor(
          of: find.text('page'),
          matching: find.byType(BackdropFilter),
        ).first,
      );
      final filter = blur.filter;
      expect(filter, isA<ImageFilter>());
      expect(filter.toString(), contains('20.0'));

      // The fill must stay light so the picture reads through.
      final fill = tester.widget<ColoredBox>(
        find
            .ancestor(
              of: find.text('page'),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(fill.color.a, lessThanOrEqualTo(0.2));
    });

    testWidgets('the player route keeps its liquid glass (not touched)', (
      tester,
    ) async {
      // The user asked to remove the outline on secondary pages ONLY.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBackgroundSettingsProvider.overrideWith(
              (ref) => _Bg(path: _realImageFile.path),
            ),
          ],
          child: MaterialApp(
            home: PlayerGlassRouteSurface(
              imageBuilder: (_) => const ColoredBox(color: Colors.red),
              child: const Text('player'),
            ),
          ),
        ),
      );

      expect(find.text('player'), findsOneWidget);
      expect(
        find.byKey(const Key('player-glass-liquid-layer')),
        findsOneWidget,
        reason: 'the player surface must keep its liquid glass',
      );
    });

    testWidgets('applies even with no background configured', (tester) async {
      // The two cases used to diverge, and "no background configured" was the only
      // configuration where a page could still show through during a transition.
      // One path means one behaviour to reason about.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBackgroundSettingsProvider.overrideWith((ref) => _Bg()),
          ],
          child: const MaterialApp(
            home: SecondaryGlassSurface(child: Text('page')),
          ),
        ),
      );

      expect(find.text('page'), findsOneWidget);
      expect(find.byKey(const Key('secondary-acrylic-surface')), findsOneWidget);
      expect(find.byType(BackdropFilter), findsWidgets);

      final fill = tester.widget<ColoredBox>(
        find
            .ancestor(
              of: find.text('page'),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(
        fill.color.a,
        lessThanOrEqualTo(0.2),
        reason: 'the fill must stay light; blur is what does the work',
      );
    });
  });

  group('a transition is masked by the acrylic, not by an opaque plate', () {
    testWidgets('the plate stays at its resting value for the whole transition', (
      tester,
    ) async {
      // The plate used to go opaque mid-transition to hide the strip the incoming
      // page had not covered yet. That stopped the leftover but introduced a worse
      // artefact: an opaque plate is a *flat colour*, so it blanked the background
      // for the whole animation and then released it — a solid-colour flash when
      // entering a page.
      //
      // The masking is now the acrylic sheet's job, and it is on the whole time. So
      // this test asserts the plate NEVER goes opaque, and that the acrylic is
      // present throughout instead. Weakening either one brings the leftover back.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(414, 820);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      appRouter.go('/');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            uiStyleProvider.overrideWith((ref) => _Style()),
            appBackgroundSettingsProvider.overrideWith((ref) => _Bg()),
            playerProvider.overrideWith(
              (ref) => PlayerNotifier(
                audioController: _Idle(),
                audioControllerFactory: _Idle.new,
              ),
            ),
          ],
          child: MaterialApp.router(
            builder: (context, child) =>
                MconnectApp.buildGlassShell(context, child, UiStyle.material),
            routerConfig: appRouter,
          ),
        ),
      );
      await tester.pump();

      List<double> plates() => tester
          .widgetList<AppBackgroundShell>(find.byType(AppBackgroundShell))
          .where((shell) => !shell.drawImage)
          .map((shell) => shell.baseOpacity)
          .toList();

      void expectNoOpaquePlate(String tag) {
        expect(
          plates().where((a) => a >= 1.0),
          isEmpty,
          reason:
              'at $tag no plate may be opaque: a flat opaque plate blanks the '
              'background and flashes',
        );
      }

      expect(plates().every((a) => a <= 0.15), isTrue);

      appRouter.push('/likes');
      await tester.pump();
      for (final step in [60, 120, 180, 240]) {
        await tester.pump(const Duration(milliseconds: 60));
        expectNoOpaquePlate('t=${step}ms');
        // The masking layer must be in the tree for the entire transition, because
        // it is what hides the page below while the new one slides in.
        expect(
          find.byKey(const Key('secondary-acrylic-surface')),
          findsWidgets,
          reason: 'the acrylic sheet must be present throughout at t=${step}ms',
        );
      }

      await tester.pump(const Duration(milliseconds: 400));
      expect(plates().every((a) => a == 0.0), isTrue);

      appRouter.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expectNoOpaquePlate('mid-pop');

      await tester.pump(const Duration(milliseconds: 400));
      expect(plates().every((a) => a <= 0.15), isTrue);
    });
  });

  testWidgets('falls back to a scrim when motion is reduced', (tester) async {
    // Reduced motion is now the only thing that skips the acrylic sheet: a live
    // backdrop filter is real per-frame work, and a user who asked for less motion
    // does not need it.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBackgroundSettingsProvider.overrideWith((ref) => _Bg()),
        ],
        child: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(home: SecondaryGlassSurface(child: Text('page'))),
        ),
      ),
    );

    expect(find.text('page'), findsOneWidget);
    expect(find.byKey(const Key('secondary-acrylic-surface')), findsNothing);
    final fallback = tester.widget<ColoredBox>(
      find
          .ancestor(of: find.text('page'), matching: find.byType(ColoredBox))
          .first,
    );
    expect(
      fallback.color.a,
      greaterThanOrEqualTo(0.5),
      reason: 'the degraded path must still dim enough to read text',
    );
    expect(tester.takeException(), isNull);
  });
}