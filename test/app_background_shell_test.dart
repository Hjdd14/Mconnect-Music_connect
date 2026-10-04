import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/theme/app_background.dart';
import 'package:mconnect/core/theme/app_background_provider.dart';

void main() {
  late Directory tempDir;
  late File imageFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_background_ui_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    imageFile = File('${tempDir.path}\\background.png');
    await imageFile.writeAsBytes(_transparentPng);
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('background shell omits image layer when disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AppBackgroundShell(child: Text('content'))),
      ),
    );

    expect(find.text('content'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('background shell renders configured image layer', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBackgroundSettingsProvider.overrideWith(
            (ref) => _FixedBackgroundNotifier(_backgroundSettings(imageFile)),
          ),
        ],
        child: MaterialApp(
          home: AppBackgroundShell(
            imageBuilder: (_) => const ColoredBox(
              key: Key('fake-background-image'),
              color: Colors.red,
              child: SizedBox.expand(),
            ),
            child: const Text('content'),
          ),
        ),
      ),
    );

    expect(find.text('content'), findsOneWidget);
    expect(find.byKey(const Key('fake-background-image')), findsOneWidget);
  });

  testWidgets('background shell renders restored background on first frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBackgroundSettingsProvider.overrideWith(
            (ref) => _FixedBackgroundNotifier(_backgroundSettings(imageFile)),
          ),
        ],
        child: MaterialApp(
          home: AppBackgroundShell(
            imageBuilder: (_) => const ColoredBox(
              key: Key('first-frame-background-image'),
              color: Colors.red,
              child: SizedBox.expand(),
            ),
            child: const Text('content'),
          ),
        ),
      ),
    );

    expect(find.text('content'), findsOneWidget);
    expect(
      find.byKey(const Key('first-frame-background-image')),
      findsOneWidget,
    );
  });

  test('background image layer preserves aspect ratio with black padding', () {
    final geometry = appBackgroundImageGeometry(
      settings: AppBackgroundSettings(
        imagePath: imageFile.path,
        imageWidth: 800,
        imageHeight: 400,
      ),
      viewportSize: const Size(300, 300),
    );

    expect(geometry.canvasSize.width, 300);
    expect(geometry.canvasSize.height, 150);
    expect(geometry.canvasOffset.dx, 0);
    expect(geometry.canvasOffset.dy, 75);
  });

  // The editor preview reads the gesture matrix through this pair, and so does
  // the dialog's save action. One definition, so the preview cannot show one
  // placement while another one is saved and painted.
  group('the editor matrix and the settings transform agree', () {
    test('a matrix round-trips through the transform', () {
      const offset = Offset(-40, 60);
      final matrix = appBackgroundMatrixFromTransform(
        scale: 2.5,
        offset: offset,
      );

      final transform = appBackgroundTransformFromMatrix(matrix);

      expect(transform.scale, 2.5);
      expect(transform.offset, offset);
    });

    test('a translation is read back unscaled', () {
      // The shape `InteractiveViewer` produces: translation first, then scale,
      // so the translation lives in storage[12]/[13] and carries no scale.
      final matrix = Matrix4.identity()
        ..translateByDouble(12, -8, 0, 1)
        ..scaleByDouble(1.75, 1.75, 1, 1);

      final transform = appBackgroundTransformFromMatrix(matrix);

      expect(transform.scale, 1.75);
      expect(transform.offset.dx, 12);
      expect(transform.offset.dy, -8);
    });

    test('the scale is clamped exactly as the stored settings are', () {
      final matrix = appBackgroundMatrixFromTransform(
        scale: 9,
        offset: Offset.zero,
      );

      expect(appBackgroundTransformFromMatrix(matrix).scale, 4);
    });
  });

  testWidgets('background image canvas paints black behind padded images', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBackgroundSettingsProvider.overrideWith(
            (ref) => _FixedBackgroundNotifier(
              AppBackgroundSettings(
                imagePath: imageFile.path,
                imageWidth: 80,
                imageHeight: 40,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          home: SizedBox(
            width: 300,
            height: 300,
            child: AppBackgroundShell(
              imageBuilder: (_) => const ColoredBox(
                key: Key('small-background-image'),
                color: Colors.red,
                child: SizedBox.expand(),
              ),
              child: const Text('content'),
            ),
          ),
        ),
      ),
    );

    final frame = tester.widget<ColoredBox>(
      find.byKey(const Key('app-background-image-frame')),
    );
    expect(frame.color, Colors.black);
    expect(find.byKey(const Key('small-background-image')), findsOneWidget);
  });

  test('large background images use a capped decode size', () {
    final decodeSize = appBackgroundImageDecodeSize(
      settings: AppBackgroundSettings(
        imagePath: imageFile.path,
        imageWidth: 9000,
        imageHeight: 4500,
      ),
    );

    expect(decodeSize.cacheWidth, 4096);
    expect(decodeSize.cacheHeight, 2048);
  });

  testWidgets('player glass surface reuses the configured image with blur', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBackgroundSettingsProvider.overrideWith(
            (ref) => _FixedBackgroundNotifier(_backgroundSettings(imageFile)),
          ),
        ],
        child: const _PlayerGlassTestApp(),
      ),
    );

    expect(find.text('player'), findsOneWidget);
    expect(find.byKey(const Key('player-glass-route-surface')), findsOneWidget);
    expect(find.byKey(const Key('player-glass-route-base')), findsOneWidget);
    expect(
      find.byKey(const Key('player-glass-background-blur')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('player-glass-route-scrim')), findsOneWidget);
    expect(
      find.byKey(const Key('fake-player-background-image')),
      findsOneWidget,
    );

    final blur = tester.widget<ImageFiltered>(
      find.byKey(const Key('player-glass-background-blur')),
    );
    final filter = blur.imageFilter;
    expect(filter, isA<ImageFilter>());
  });

  testWidgets('player glass surface falls back to theme surface without image', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PlayerGlassRouteSurface(child: Text('player'))),
      ),
    );

    expect(find.text('player'), findsOneWidget);
    expect(
      find.byKey(const Key('player-glass-route-surface')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('player-glass-route-base')), findsOneWidget);
    expect(
      find.byKey(const Key('player-glass-background-blur')),
      findsNothing,
    );
    expect(find.byType(Image), findsNothing);
  });

  group('the background image is painted exactly once', () {
    testWidgets('a shell with drawImage: false contributes no image', (
      tester,
    ) async {
      // Route shells used to paint their own copy. `appBackgroundImageGeometry`
      // scales the image to whichever viewport it is handed, and a route shell's
      // viewport is smaller than the app shell's (the app shell also covers the
      // Scaffold's bottom inset), so the two copies came out at different sizes —
      // the "重复 / 缩小 / 黑边" that was reported.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBackgroundSettingsProvider.overrideWith(
              (ref) => _FixedBackgroundNotifier(_backgroundSettings(imageFile)),
            ),
          ],
          child: MaterialApp(
            home: SizedBox(
              width: 300,
              height: 300,
              child: AppBackgroundShell(
                drawImage: false,
                imageBuilder: (_) => const ColoredBox(
                  key: Key('route-copy-image'),
                  color: Colors.red,
                  child: SizedBox.expand(),
                ),
                child: const Text('content'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('content'), findsOneWidget);
      expect(
        find.byKey(const Key('app-background-image-frame')),
        findsNothing,
        reason: 'a route backing must not paint the image a second time',
      );
      expect(find.byKey(const Key('route-copy-image')), findsNothing);
      // …but it must still be opaque enough to mask the page below it.
      final base = tester.widget<ColoredBox>(
        find
            .ancestor(
              of: find.text('content'),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(base.color.a, greaterThan(0.8));
    });

    testWidgets('drawImage: true still paints the image once', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBackgroundSettingsProvider.overrideWith(
              (ref) => _FixedBackgroundNotifier(_backgroundSettings(imageFile)),
            ),
          ],
          child: MaterialApp(
            home: SizedBox(
              width: 300,
              height: 300,
              child: AppBackgroundShell(
                imageBuilder: (_) => const ColoredBox(
                  key: Key('app-copy-image'),
                  color: Colors.red,
                  child: SizedBox.expand(),
                ),
                child: const Text('content'),
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const Key('app-background-image-frame')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('app-copy-image')), findsOneWidget);
    });

    testWidgets('the image frame is not painted on a black plate', (
      tester,
    ) async {
      // `Colors.black` behind the image canvas is what showed up as black bars
      // once a copy was scaled down. Only the real image layer should exist, and
      // it must not be sitting on black.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBackgroundSettingsProvider.overrideWith(
              (ref) => _FixedBackgroundNotifier(_backgroundSettings(imageFile)),
            ),
          ],
          child: MaterialApp(
            home: SizedBox(
              width: 300,
              height: 300,
              child: AppBackgroundShell(
                imageBuilder: (_) => const ColoredBox(
                  key: Key('only-image'),
                  color: Colors.red,
                  child: SizedBox.expand(),
                ),
                child: const Text('content'),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('app-background-image-frame')), findsOneWidget);
      expect(find.byKey(const Key('only-image')), findsOneWidget);
    });
  });

  group('the player route is liquid glass', () {
    testWidgets('a glass layer sits over the artwork', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBackgroundSettingsProvider.overrideWith(
              (ref) => _FixedBackgroundNotifier(_backgroundSettings(imageFile)),
            ),
          ],
          child: const _PlayerGlassTestApp(),
        ),
      );

      // The glass samples what is painted before it, so the artwork must come
      // first in the stack.
      expect(find.byKey(const Key('player-glass-liquid-layer')), findsOneWidget);

      final stack = tester.widget<Stack>(
        find.byKey(const Key('player-glass-route-surface')),
      );
      final glassIndex = stack.children.indexWhere(
        (w) => w is Positioned && w.child is IgnorePointer,
      );
      final blurIndex = stack.children.indexWhere(
        (w) => w is Positioned && w.child is ImageFiltered,
      );
      expect(blurIndex, isNonNegative);
      expect(
        blurIndex,
        lessThan(glassIndex),
        reason: 'the glass must be able to sample the artwork below it',
      );
    });

    testWidgets('glass does not need a wrap() ancestor', (tester) async {
      // `InheritedLiquidGlass.of` and `LiquidGlassScope.of` both return null when
      // no `LiquidGlassWidgets.wrap` is present, so the player route must render
      // under a plain `MaterialApp` without throwing — which is also what keeps
      // `UiStyle.material` working.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appBackgroundSettingsProvider.overrideWith(
              (ref) => _FixedBackgroundNotifier(_backgroundSettings(imageFile)),
            ),
          ],
          child: const _PlayerGlassTestApp(),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('player'), findsOneWidget);
    });
  });
}

AppBackgroundSettings _backgroundSettings(File imageFile) {
  return AppBackgroundSettings(
    imagePath: imageFile.path,
    imageWidth: 1,
    imageHeight: 1,
    scale: 1.25,
    offsetX: 8,
    offsetY: -6,
  );
}

class _FixedBackgroundNotifier extends AppBackgroundSettingsNotifier {
  _FixedBackgroundNotifier(AppBackgroundSettings settings) {
    state = settings;
  }
}

class _PlayerGlassTestApp extends StatelessWidget {
  const _PlayerGlassTestApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: PlayerGlassRouteSurface(
        imageBuilder: (_) => const ColoredBox(
          key: Key('fake-player-background-image'),
          color: Colors.red,
          child: SizedBox.expand(),
        ),
        child: const Text('player'),
      ),
    );
  }
}

const _transparentPng = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
