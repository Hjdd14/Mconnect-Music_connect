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

  testWidgets(
    'player glass surface falls back to theme surface without image',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PlayerGlassRouteSurface(child: Text('player')),
          ),
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
    },
  );
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
