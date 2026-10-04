import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/app.dart';
import 'package:mconnect/core/router/app_router.dart';
import 'package:mconnect/core/theme/app_background_provider.dart';
import 'package:mconnect/core/theme/ui_style_provider.dart';
import 'package:mconnect/core/widgets/miuix_bottom_layout.dart';
import 'package:mconnect/core/widgets/miuix_bottom_stack.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';

/// The frosted sheet on a secondary page paints its **own** copy of the user's
/// picture, on purpose — see `SecondaryGlassSurface`. That is only safe if the two
/// copies land on exactly the same pixels.
///
/// They must therefore agree on one viewport. The app-level shell measures it and
/// publishes it (`AppBackgroundViewport`); the sheet lays its picture out at that
/// size, and `test/app_background_shell_test.dart` pins the publishing rule.
///
/// This file measures the *result* rather than the mechanism, and it also guards
/// the defect this round fixed: the sheet must cover the **whole** viewport. It
/// used to stop at the routed box's bottom edge because the bottom clearance was a
/// `Padding` around go_router's nested Navigator — a band no route inside it can
/// paint into — leaving a sharp strip over the capsule area for the length of a
/// pop.
///
/// Same shape as 阶段 Q's assertion for the editor preview: "preview == product"
/// measured, not argued.
///
/// A 1x1 transparent PNG. The picture's *layout* box comes from the stored
/// `imageWidth`/`imageHeight`, so a 1x1 file is enough and keeps the test hermetic.
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

late File _imageFile;
late Directory _tempDir;

class _Style extends UiStyleNotifier {
  _Style() : super(initialStyle: UiStyle.material);
}

/// A deliberately non-square picture (800x400 in a 400x820 viewport) so the
/// `BoxFit.contain` letterbox and the vertical centring offset both matter. With a
/// full-viewport canvas a stale viewport could hide inside the numbers; with this
/// one the vertical offset differs by the inset, so a broken pinning cannot pass.
class _Bg extends AppBackgroundSettingsNotifier {
  _Bg({String? path})
    : super() {
    state = AppBackgroundSettings(
      imagePath: path,
      imageWidth: path == null ? 0 : 800,
      imageHeight: path == null ? 0 : 400,
    );
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

const _canvasKey = Key('app-background-image-canvas');
const _baseKey = Key('secondary-acrylic-base');

void main() {
  setUp(() async {
    _tempDir = await Directory.systemTemp.createTemp('mconnect_plate_geom_');
    _imageFile = File('${_tempDir.path}/bg.png');
    await _imageFile.writeAsBytes(_png);
  });

  tearDown(() async {
    if (await _tempDir.exists()) {
      await _tempDir.delete(recursive: true);
    }
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          uiStyleProvider.overrideWith((ref) => _Style()),
          appBackgroundSettingsProvider.overrideWith(
            (ref) => _Bg(path: _imageFile.path),
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
  }

  List<Rect> canvasRects(WidgetTester tester) {
    final finder = find.byKey(_canvasKey);
    return [
      for (var i = 0; i < finder.evaluate().length; i++)
        tester.getRect(finder.at(i)),
    ];
  }

  testWidgets('the home route paints the picture exactly once', (tester) async {
    // No plate on the home route (its backing stays a 0.08 dim), so there is one
    // copy and nothing to compare — the baseline this file measures against.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 820);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    appRouter.go('/');
    await pumpApp(tester);

    expect(find.byKey(_canvasKey), findsOneWidget);
  });

  testWidgets(
    'every copy of the picture lands on the identical rect, inset or not',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(400, 820);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      appRouter.go('/');
      await pumpApp(tester);
      final onHome = canvasRects(tester);
      expect(onHome, hasLength(1));

      appRouter.push('/likes');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      final onLikes = canvasRects(tester);
      expect(
        onLikes.length,
        greaterThanOrEqualTo(2),
        reason:
            'the app-level copy plus at least one frosted plate copy should be '
            'painted on a secondary page',
      );

      for (final rect in onLikes) {
        expect(
          rect,
          onHome.single,
          reason:
              'a second copy of the picture at a different scale or offset is the '
              '"重复 / 缩小 / 黑边" defect: both copies must be laid out from the '
              'app-level viewport, never from the routed (bottom-inset) box',
        );
      }
    },
  );

  testWidgets('the frosted sheet spans the whole viewport while content clears '
      'the capsules', (tester) async {
    // THE regression guard for the reported defect: on leaving a secondary page the
    // bottom ~20 % of the screen stayed **sharp** while everything above it was
    // frosted, for the length of the pop.
    //
    // Cause: the bottom clearance used to be a `Padding` *around* go_router's nested
    // Navigator, so no route inside it could paint below `H - inset` —
    // `_RenderTheater.paint` clips to its own bounds. The only patch for that band
    // was the root shell page's sheet, which is gated on `state.uri.path == '/'` and
    // therefore vanished on the pop's first frame while the page sliding away kept
    // its own sheet for another 220 ms.
    //
    // So there are two halves to pin, and a fix that satisfies only one is not a fix:
    //   * the sheet must cover the FULL viewport at every moment of the transition
    //     (this is what fails on the pre-fix code: height 820 - 136 = 684);
    //   * the page content must still stop short of the capsules.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 820);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const viewport = Size(400, 820);

    void expectSheetCoversViewport(String tag) {
      final plates = find.byKey(_baseKey);
      expect(
        plates,
        findsWidgets,
        reason: 'the frosted sheet must be present at $tag',
      );
      for (var i = 0; i < plates.evaluate().length; i++) {
        final rect = tester.getRect(plates.at(i));
        expect(
          rect.width,
          closeTo(viewport.width, 0.5),
          reason: 'the sheet must span the full width at $tag',
        );
        expect(
          rect.height,
          closeTo(viewport.height, 0.5),
          reason:
              'at $tag the sheet must reach the bottom edge. A shorter sheet leaves '
              'an un-frosted band over the capsule area, which is the sharp strip the '
              'user saw while a page was leaving',
        );
      }
    }

    appRouter.go('/');
    await pumpApp(tester);

    appRouter.push('/likes');
    await tester.pump();
    for (final step in [60, 120, 180]) {
      await tester.pump(const Duration(milliseconds: 60));
      expectSheetCoversViewport('mid-push t=${step}ms');
    }

    await tester.pump(const Duration(milliseconds: 600));
    expectSheetCoversViewport('settled at /likes');

    appRouter.pop();
    await tester.pump();
    for (final step in [60, 120, 180]) {
      await tester.pump(const Duration(milliseconds: 60));
      expectSheetCoversViewport('mid-pop t=${step}ms');
    }

    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('page content still stops short of the floating capsules', (
    tester,
  ) async {
    // The other half of the same change: moving the clearance from around the
    // Navigator into each route must not let content slide back under the mini
    // player / nav capsule.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 820);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    appRouter.go('/likes');
    await pumpApp(tester);
    await tester.pump(const Duration(milliseconds: 600));

    final insetHost = find.byType(RouteBottomInset);
    expect(insetHost, findsWidgets);

    final expectedInset =
        MiuixBottomLayout.playerBottomInsetFor(
          tester.element(insetHost.first),
          UiStyle.material,
        ) +
        MiuixBottomLayout.playerHeight;

    final content = tester.getRect(
      find
          .descendant(of: insetHost.first, matching: find.byType(Scaffold))
          .first,
    );

    expect(
      content.height,
      closeTo(820 - expectedInset, 0.5),
      reason:
          'the routed content must reserve the floating stack clearance '
          '($expectedInset dp), even though the sheet above it does not',
    );
    expect(
      content.bottom,
      lessThan(820),
      reason: 'content reaching the bottom edge would sit under the capsules',
    );
  });
}
