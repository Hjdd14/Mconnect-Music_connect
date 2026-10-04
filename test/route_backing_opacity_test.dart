import 'dart:io';
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

  group('the background image is painted once per visible layer', () {
    testWidgets('only the app shell and the frosted sheet paint a copy', (
      tester,
    ) async {
      // This used to assert "exactly one layer may paint the background image". The
      // reason was the "重复 / 缩小 / 黑边" defect: two copies at two different
      // *scales* composited over each other.
      //
      // The frosted sheet now paints a copy on purpose — it has to, because its
      // floor must be opaque to mask the page below while still showing the picture.
      // That is only safe because the copy is pinned to `AppBackgroundViewport`, so
      // the two are laid out from identical inputs. The scale invariant is asserted
      // by `test/secondary_plate_geometry_test.dart` (rect equality); here we pin the
      // *count and routing*: exactly one `AppBackgroundShell` paints the picture, and
      // no route plate does.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      appRouter.go('/');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            uiStyleProvider.overrideWith((ref) => _Style()),
            appBackgroundSettingsProvider.overrideWith(
              (ref) => _Bg(path: _realImageFile.path),
            ),
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
        reason: 'exactly one ImageFiltered-free shell paints the sharp picture',
      );
      expect(without, greaterThanOrEqualTo(1));
    });
  });

  group('the secondary sheet is self-contained, not a live backdrop filter', () {
    test('blurs with a near-clear fill and no outline machinery', () {
      // The liquid-glass outline could not be removed through the package API: the
      // rim comes from `GlassEffect`'s own `rimThickness` / `rimSmoothing` /
      // `edgeAlphaMultiplier`, which are not fields of `LiquidGlassSettings` and are
      // not exposed by `GlassContainer` either. Zeroing `lightIntensity`,
      // `fresnelStrength` and `glowIntensity` therefore left the outline intact.
      //
      // Acrylic removed it by construction (no edge-drawing code at all), and the
      // sheet is now self-contained as well — see the next test for why.
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

    testWidgets('no BackdropFilter and no GlassContainer anywhere in the sheet', (
      tester,
    ) async {
      // THE regression guard for the "白影" (a blurred ghost of the previous page's
      // text seen *through* the panel).
      //
      // A `BackdropFilter` filters the already-composited scene at its paint
      // position, and `TransitionRoute._handleStatusChanged` keeps the outgoing
      // route painted (`overlayEntries.first.opaque = false`) for the whole
      // forward/reverse window. So any backdrop filter here necessarily samples the
      // previous page — which is exactly how its white text got smeared into the
      // panel. `ImageFiltered` filters only its own child, so it cannot.
      //
      // This assertion is therefore not cosmetic: "no BackdropFilter in this
      // subtree" *is* the proof that no other route can reach the sheet.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBackgroundSettingsProvider.overrideWith(
              (ref) => _Bg(path: _realImageFile.path),
            ),
          ],
          child: MaterialApp(
            home: SecondaryGlassSurface(
              imageBuilder: (_) => const ColoredBox(
                key: Key('fake-frosted-image'),
                color: Colors.red,
                child: SizedBox.expand(),
              ),
              child: const Text('page'),
            ),
          ),
        ),
      );

      expect(find.text('page'), findsOneWidget);
      expect(
        find.byType(BackdropFilter),
        findsNothing,
        reason:
            'a backdrop filter samples the live scene, which during a transition '
            'still contains the outgoing route — that is the ghost',
      );
      expect(
        find.byType(GlassContainer),
        findsNothing,
        reason: 'a GlassContainer would paint the rim again',
      );

      // The blur now runs over the sheet's own copy of the picture.
      final frosted = tester.widget<ImageFiltered>(
        find.byKey(const Key('secondary-acrylic-frosted-image')),
      );
      expect(frosted.imageFilter.toString(), contains('20.0'));
      expect(find.byKey(const Key('fake-frosted-image')), findsOneWidget);

      // The fill must stay light so the picture reads through.
      final fill = tester.widget<ColoredBox>(
        find.byKey(const Key('secondary-acrylic-surface')),
      );
      expect(fill.color.a, lessThanOrEqualTo(0.2));
    });

    testWidgets('the masking floor is opaque', (tester) async {
      // Masking is structural now: an opaque floor plus a picture the sheet paints
      // itself. Because that floor *is* the (blurred) background, "opaque" no longer
      // costs the user their background — which is what made the old fill-only
      // approach unsolvable.
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

      final base = tester.widget<ColoredBox>(
        find.byKey(const Key('secondary-acrylic-base')),
      );
      expect(
        base.color.a,
        1.0,
        reason:
            'a translucent floor would let the outgoing route composite through, '
            'which is the ghost',
      );
    });

    testWidgets('still opaque with no background configured', (tester) async {
      // The two cases used to diverge, and "no background configured" was the only
      // configuration where a page could still show through during a transition.
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
      final base = tester.widget<ColoredBox>(
        find.byKey(const Key('secondary-acrylic-base')),
      );
      expect(base.color.a, 1.0);
      expect(
        find.byKey(const Key('secondary-acrylic-frosted-image')),
        findsNothing,
        reason: 'nothing to blur when the user has not chosen a picture',
      );
      expect(find.byType(BackdropFilter), findsNothing);
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
  });

  group('a transition is masked by the frosted sheet, not by a flat plate', () {
    testWidgets('the plate stays at its resting value for the whole transition', (
      tester,
    ) async {
      // The *route backing plate* used to go opaque mid-transition to hide the strip
      // the incoming page had not covered yet. That stopped the leftover but
      // introduced a worse artefact: an opaque plate is a *flat colour*, so it
      // blanked the background for the whole animation and then released it — a
      // solid-colour flash when entering a page.
      //
      // Masking is now the frosted sheet's job: it is opaque, always on, and its
      // floor is the user's own (blurred) picture rather than a flat colour, so
      // being opaque costs nothing visually. This test asserts the *plate* still
      // never goes opaque, and that the sheet's opaque floor and tint are both
      // present throughout.
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
              'at $tag no *plate* may be opaque: a flat opaque plate blanks the '
              'background and flashes',
        );
      }

      void expectMaskedThroughout(String tag) {
        expect(
          find.byKey(const Key('secondary-acrylic-base')),
          findsWidgets,
          reason: 'the opaque floor must be present throughout at $tag',
        );
        expect(
          find.byKey(const Key('secondary-acrylic-surface')),
          findsWidgets,
          reason: 'the frosted sheet must be present throughout at $tag',
        );
      }

      expect(plates().every((a) => a <= 0.15), isTrue);

      appRouter.push('/likes');
      await tester.pump();
      for (final step in [60, 120, 180, 240]) {
        await tester.pump(const Duration(milliseconds: 60));
        expectNoOpaquePlate('t=${step}ms');
        expectMaskedThroughout('t=${step}ms');
      }

      await tester.pump(const Duration(milliseconds: 400));
      expect(plates().every((a) => a == 0.0), isTrue);

      appRouter.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expectNoOpaquePlate('mid-pop');
      expectMaskedThroughout('mid-pop');

      await tester.pump(const Duration(milliseconds: 400));
      expect(plates().every((a) => a <= 0.15), isTrue);
    });
  });

  testWidgets('the sheet masks whether or not motion is reduced', (tester) async {
    // This used to be the only branch that skipped the sheet: it fell back to a
    // `surface` scrim at alpha 0.6. That scrim is translucent, so for the whole
    // route animation (280 ms forward / 220 ms reverse) the outgoing route still
    // composited through it at 40 % — a double exposure for users who asked for
    // less motion.
    //
    // The blur is static work, not motion, so the motion preference no longer
    // changes the material at all. One path means one behaviour to reason about.
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
    expect(find.byKey(const Key('secondary-acrylic-base')), findsOneWidget);
    expect(
      find.byKey(const Key('secondary-glass-surface-fallback')),
      findsNothing,
      reason: 'the translucent scrim fallback is what leaked the page below',
    );
    final base = tester.widget<ColoredBox>(
      find.byKey(const Key('secondary-acrylic-base')),
    );
    expect(base.color.a, 1.0);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });
}