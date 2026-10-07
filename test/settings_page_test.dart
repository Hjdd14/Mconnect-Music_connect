import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/diagnostics/diagnostics_service.dart';
import 'package:mconnect/core/theme/app_background.dart';
import 'package:mconnect/core/theme/app_background_provider.dart';
import 'package:mconnect/features/settings/presentation/pages/settings_page.dart';

void main() {
  late Directory tempDir;
  late File imageFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_settings_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await DiagnosticsService.instance.initializeForTest(tempDir);
    // `AppBackgroundImageLayer` skips a missing file before it ever asks the
    // injected `imageBuilder` for pixels, so the shell needs a real path.
    imageFile = File('${tempDir.path}${Platform.pathSeparator}background.png');
    await imageFile.writeAsBytes(_transparentPng);
  });

  tearDown(() async {
    await DiagnosticsService.instance.flush();
    await DiagnosticsService.instance.resetForTest();
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('settings page exposes diagnostics log path', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsDiagnosticsPage())),
    );

    await tester.scrollUntilVisible(
      find.text('诊断日志'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('诊断日志'), findsOneWidget);
    expect(find.textContaining('mconnect.log'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsWidgets);
  });

  testWidgets('settings page shows the current app version', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsDiagnosticsPage())),
    );

    await tester.scrollUntilVisible(
      find.text('版本'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('v1.4.3'), findsOneWidget);
  });

  testWidgets(
    'settings home exposes section entry points',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SettingsPage())),
      );

      for (final label in const [
        '账号管理',
        '外观',
        '悬浮歌词',
        '音频增强',
        '诊断与关于',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
    },
  );

  testWidgets(
    'appearance settings page exposes theme color and background controls',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SettingsAppearancePage())),
      );

      expect(find.text('主题色'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('app-background-tile')),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('app-background-tile')), findsOneWidget);
    },
  );

  testWidgets(
    'floating lyrics settings page exposes lyrics controls',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: SettingsFloatingLyricsPage()),
        ),
      );

      for (final label in const [
        '桌面悬浮歌词',
        '锁定位置',
        '歌词底色',
        '已播放高亮色',
        '字号',
      ]) {
        await _dragUntilTextVisible(tester, label);
        expect(find.text(label), findsOneWidget);
      }
      expect(
        find.byKey(const Key('floating-lyrics-lock-tile')),
        findsOneWidget,
      );
    },
  );

  testWidgets('floating lyrics color rows open a full color picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SettingsFloatingLyricsPage()),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('floating-lyrics-text-color-tile')),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    final colorTile = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const Key('floating-lyrics-text-color-tile')),
        matching: find.byType(ListTile),
      ),
    );
    colorTile.onTap!();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('floating-color-picker-dialog')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('floating-color-picker-hue')), findsOneWidget);
    expect(
      find.byKey(const Key('floating-color-picker-saturation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('floating-color-picker-value')),
      findsOneWidget,
    );
  });

  testWidgets('floating lyrics rows expose a clear custom color entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SettingsFloatingLyricsPage()),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('floating-lyrics-text-color-tile')),
      220,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('自定义颜色'), findsWidgets);
    final colorTile = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const Key('floating-lyrics-text-color-tile')),
        matching: find.byType(ListTile),
      ),
    );
    colorTile.onTap!();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('floating-color-picker-dialog')),
      findsOneWidget,
    );
  });

  testWidgets('settings page exposes low-risk audio enhancement controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsAudioPage())),
    );

    for (final label in const [
      '淡入淡出',
      '淡入淡出时长',
      '均衡器',
      '均衡器预设',
      '低频',
      '中频',
      '高频',
      '睡眠定时',
      '定时时长',
    ]) {
      await _dragUntilTextVisible(tester, label);
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets(
    'appearance settings page exposes the ui style switch',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SettingsAppearancePage())),
      );

      expect(find.text('UI 风格'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('ui-style-tile')),
        220,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.byKey(const Key('ui-style-tile')), findsOneWidget);
      expect(find.text('Material 风格'), findsOneWidget);
      expect(find.text('Miuix 风格'), findsOneWidget);
    },
  );

  testWidgets(
    'appearance settings page keeps the existing controls above the ui style switch',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SettingsAppearancePage())),
      );

      for (final label in const ['跟随系统', '浅色模式', '深色模式', '主题色']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.scrollUntilVisible(
        find.byKey(const Key('app-background-tile')),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('app-background-tile')), findsOneWidget);
    },
  );

  test('background editor uses a landscape crop shape on wide windows', () {
    final crop = backgroundCropViewportSize(const Size(1200, 800));

    expect(crop.width / crop.height, greaterThan(1));
  });

  test('background editor uses a portrait crop shape on tall windows', () {
    final crop = backgroundCropViewportSize(const Size(390, 844));

    expect(crop.width / crop.height, lessThan(1));
  });

  test('background destination paths are unique', () {
    final first = createBackgroundDestinationPath(
      backgroundsDirPath: 'D:\\App\\backgrounds',
      originalName: 'wallpaper.jpg',
      now: DateTime.fromMicrosecondsSinceEpoch(100),
    );
    final second = createBackgroundDestinationPath(
      backgroundsDirPath: 'D:\\App\\backgrounds',
      originalName: 'wallpaper.jpg',
      now: DateTime.fromMicrosecondsSinceEpoch(101),
    );

    expect(first, isNot(second));
    expect(first, contains('custom_background_100.jpg'));
    expect(second, contains('custom_background_101.jpg'));
  });

  test('small background images are accepted for black padded placement', () {
    expect(
      canUseDecodedBackgroundImage(imageWidth: 32, imageHeight: 24),
      isTrue,
    );
  });

  // The editor preview and the app background are two different widget trees,
  // but they must place the image in the same place. These tests pin that by
  // comparing the preview against the app-level shell at one window size, both
  // untouched and after a drag. The shell scales about the *viewport centre*
  // (Flutter's `Transform.scale` default alignment); the editor used to scale
  // about the child's top-left through `InteractiveViewer`, which offset every
  // saved position by `(1 - scale) * centre` — the "actual background sits
  // down-right of the preview" report.
  group('background editor preview matches the app background', () {
    testWidgets('the preview places the image exactly where the shell does', (
      tester,
    ) async {
      _useTestWindow(tester);
      final settings = _editorSettings(imageFile.path);

      await tester.pumpWidget(_appBackgroundShellWith(settings));
      final shellRel = _backgroundCanvasOrigin(tester);
      final shellSize = _backgroundFrameSize(tester);

      // The app-level invariant both paths must reproduce: a 200x400 image in a
      // 400x700 viewport is canvased at (25, 0) and, at scale 2, lands at
      // centre + 2 * (canvasOffset - centre) = (-150, -350).
      expect(shellRel.dx, closeTo(-150, 0.5));
      expect(shellRel.dy, closeTo(-350, 0.5));

      await tester.pumpWidget(
        MaterialApp(
          home: BackgroundEditorDialog(
            settings: settings,
            imageBuilder: _stubBackgroundImage,
          ),
        ),
      );
      await tester.pump();

      final previewRel = _backgroundCanvasOrigin(tester);
      final previewSize = _backgroundFrameSize(tester);

      expect(
        previewRel.dx,
        closeTo(shellRel.dx * previewSize.width / shellSize.width, 0.01),
        reason: 'the preview must be the app background, scaled to the dialog',
      );
      expect(
        previewRel.dy,
        closeTo(shellRel.dy * previewSize.height / shellSize.height, 0.01),
        reason: 'the preview must be the app background, scaled to the dialog',
      );
    });

    testWidgets('saving the editor reproduces what the preview showed', (
      tester,
    ) async {
      _useTestWindow(tester);
      final settings = _editorSettings(imageFile.path);
      AppBackgroundSettings? saved;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  saved = await showDialog<AppBackgroundSettings>(
                    context: context,
                    builder: (_) => BackgroundEditorDialog(
                      settings: settings,
                      imageBuilder: _stubBackgroundImage,
                    ),
                  );
                },
                child: const Text('打开背景编辑器'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开背景编辑器'));
      await tester.pumpAndSettle();

      final before = _backgroundCanvasOrigin(tester);
      await tester.drag(
        find.byKey(const Key('app-background-editor-preview')),
        const Offset(-40, -60),
      );
      await tester.pumpAndSettle();

      final previewRel = _backgroundCanvasOrigin(tester);
      final previewSize = _backgroundFrameSize(tester);
      // The drag has to reach the preview at all: the gesture surface must be the
      // top-most layer, or the rendered canvas below swallows the pointer.
      expect(previewRel.dx, closeTo(before.dx - 40, 0.5));
      expect(previewRel.dy, closeTo(before.dy - 60, 0.5));

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);

      await tester.pumpWidget(_appBackgroundShellWith(saved!));
      final shellRel = _backgroundCanvasOrigin(tester);
      final shellSize = _backgroundFrameSize(tester);

      expect(
        previewRel.dx,
        closeTo(shellRel.dx * previewSize.width / shellSize.width, 0.01),
        reason: 'saving must produce exactly the picture the user dragged',
      );
      expect(
        previewRel.dy,
        closeTo(shellRel.dy * previewSize.height / shellSize.height, 0.01),
        reason: 'saving must produce exactly the picture the user dragged',
      );
    });
  });
}

/// Runs the test on the window size these expectations are derived from.
void _useTestWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The zoomed-in background a 400x700 window and a 200x400 picture produce.
AppBackgroundSettings _editorSettings(String imagePath) {
  return AppBackgroundSettings(
    imagePath: imagePath,
    imageWidth: 200,
    imageHeight: 400,
    scale: 2,
    cropViewportWidth: 400,
    cropViewportHeight: 700,
  );
}

Widget _appBackgroundShellWith(AppBackgroundSettings settings) {
  return ProviderScope(
    overrides: [
      appBackgroundSettingsProvider.overrideWith(
        (ref) => _FixedBackgroundNotifier(settings),
      ),
    ],
    child: MaterialApp(
      home: AppBackgroundShell(
        imageBuilder: _stubBackgroundImage,
        child: const SizedBox.expand(),
      ),
    ),
  );
}

/// Where the image canvas origin sits relative to the frame that clips it.
///
/// Both trees expose the same two keys, so comparing this offset — scaled by the
/// viewport ratio — is the whole "preview equals the real background" contract.
Offset _backgroundCanvasOrigin(WidgetTester tester) {
  final frame = tester.getTopLeft(
    find.byKey(const Key('app-background-image-frame')),
  );
  final canvas = tester.getTopLeft(
    find.byKey(const Key('app-background-image-canvas')),
  );
  return canvas - frame;
}

Size _backgroundFrameSize(WidgetTester tester) =>
    tester.getSize(find.byKey(const Key('app-background-image-frame')));

Widget _stubBackgroundImage(File file) {
  return const ColoredBox(
    key: Key('stub-background-image'),
    color: Colors.red,
    child: SizedBox.expand(),
  );
}

class _FixedBackgroundNotifier extends AppBackgroundSettingsNotifier {
  _FixedBackgroundNotifier(AppBackgroundSettings settings) {
    state = settings;
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

Future<void> _dragUntilTextVisible(WidgetTester tester, String label) async {
  for (var i = 0; i < 10; i++) {
    if (find.text(label).evaluate().isNotEmpty) return;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
    await tester.pumpAndSettle();
  }
}
