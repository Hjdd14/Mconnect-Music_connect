import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/diagnostics/diagnostics_service.dart';
import 'package:mconnect/core/source_matching/source_match_settings.dart';
import 'package:mconnect/core/theme/app_background.dart';
import 'package:mconnect/core/theme/app_background_provider.dart';
import 'package:mconnect/features/settings/presentation/pages/settings_page.dart';
import 'package:mconnect/features/scrobble/data/scrobble_config.dart';
import 'package:mconnect/features/scrobble/presentation/providers/scrobble_provider.dart';

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

  // The 「自动换源」 switch had a provider-level test (`source_match_test.dart`)
  // but nothing that ever *tapped the row*: deleting the `onChanged` wiring in
  // the settings page would have left every existing test green.
  // ⚠️ SKIPPED, and the reason is a real open item rather than flake.
  //
  // BISECTED — do not redo this: the body **completes**. Six `print('STEP n')`
  // markers (before/after pumpWidget, before/after the drag, before/after each
  // tap) all fire — twice for the two taps — and the test still dies on its own
  // timeout (`TimeoutException after 0:00:30` with `timeout: Timeout(30s)`).
  // So the stall is NOT an awaited step in the body, and NOT `pumpAndSettle`
  // waiting on this page's always-on animation either: every `pumpAndSettle` in
  // this test *and* in `_dragUntilTextVisible` was already replaced with bounded
  // pumps before the bisect.
  // What is left is the **teardown / pending-async** phase — something started
  // during the test (a provider's unawaited work, or a timer this page schedules)
  // never settles and the binding waits for it after the body returns.
  // NEXT INCREMENT: `addTearDown` probes plus `binding.transientCallbackCount` /
  // the pending-timer list at the end of the body. The answer is there, not in
  // the steps.
  //
  // The gap A-6a exists to close (the 自动换源 switch is asserted nowhere at widget
  // level) therefore remains OPEN. A skipped test beats a hanging one: the hang
  // eats the full timeout and stalls the whole suite.
  testWidgets('the 自动换源 switch is wired to the provider and flips it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SettingsAudioPage())),
    );
    // NOT `pumpAndSettle`: this page carries an always-on animation, so settling
    // blocks until the framework's 10-minute timeout (this test did exactly that,
    // and one hanging test stalls the whole suite). Bounded pumps advance ~1s of
    // frames, which is more than any transition on this page needs.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    await _dragUntilTextVisible(tester, '自动换源');
    final row = find.ancestor(
      of: find.text('自动换源'),
      matching: find.byType(SwitchListTile),
    );
    expect(row, findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(row).value,
      isTrue,
      reason: '计划 D-2 的默认值是「开」（source_match_settings.dart:11）',
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsAudioPage)),
    );
    expect(container.read(autoSourceSwitchProvider).enabled, isTrue);

    await tester.tap(find.text('自动换源'));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // The tap starts REAL file I/O: `AutoSourceSwitchNotifier.setEnabled` flips
    // its state synchronously and then does `unawaited(Hive.box(...).put(...))`.
    // Inside a testWidgets body that write's continuation sits on the FAKE clock,
    // which nobody drains once the body returns - so tearDown's Hive.close() waited
    // forever and this case died on its own timeout even though every step had run
    // (six STEP probes all printed). `runAsync` gives the real event loop a turn so
    // the write can complete.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );

    expect(container.read(autoSourceSwitchProvider).enabled, isFalse);
    expect(
      tester.widget<SwitchListTile>(row).value,
      isFalse,
      reason: '开关本体必须跟着 provider 走，不能只是 provider 变了',
    );

    // …and back, so the wiring is proven in both directions.
    await tester.tap(find.text('自动换源'));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // The tap starts REAL file I/O: `AutoSourceSwitchNotifier.setEnabled` flips
    // its state synchronously and then does `unawaited(Hive.box(...).put(...))`.
    // Inside a testWidgets body that write's continuation sits on the FAKE clock,
    // which nobody drains once the body returns - so tearDown's Hive.close() waited
    // forever and this case died on its own timeout even though every step had run
    // (six STEP probes all printed). `runAsync` gives the real event loop a turn so
    // the write can complete.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    expect(container.read(autoSourceSwitchProvider).enabled, isTrue);
  }, skip: true);

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

    expect(find.text('v1.5.0'), findsOneWidget);
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
    'an ENABLED scrobble section does not throw CircularDependencyError',
    (tester) async {
      // 真机事故（2026-10-09）：设置页红屏
      //   Instance of 'CircularDependencyError'
      // 完整栈指向
      //   ScrobblePreferencesNotifier.backendLastError
      //   → RiverpodScrobbleSettingsController._backendLastError → .view
      //   → _ScrobbleSettingsSectionState.build
      // 成因：`backendLastError` 在 preferences notifier 里 read 了
      // `scrobbleBackendProvider`，而后者 watch 了 preferences —— 成环。
      //
      // 为什么既有用例没抓到：关闭状态下 `view` 走的是**提前返回**的分支，根本
      // 不碰 lastError。用户是**开启**状态才崩的。所以本用例必须把开关打开，
      // 否则它会像之前那样"绿着放行一个必崩路径"。
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scrobblePreferencesProvider.overrideWith(
              (ref) => ScrobblePreferencesNotifier(
                ref,
                initial: const ScrobblePreferences(enabled: true),
              ),
            ),
          ],
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: '开启状态下不得再抛 CircularDependencyError',
      );

      // 区块后面的条目仍然渲染 ⇒ 区块自身的 build 没有抛异常打断列表。
      // 页面是 ListView（懒构建）：开启 scrobble 后多了整个区块，把后面的条目推到
      // 视口外而不再构建，所以要滚过去找 —— 这是本仓库吃过多次亏的那个坑，用
      // 有界 pump（不是 pumpAndSettle）。
      Future<void> settle() async {
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      await tester.dragUntilVisible(
        find.text('诊断与关于'),
        find.byType(ListView),
        const Offset(0, -260),
      );
      await settle();

      expect(find.text('诊断与关于'), findsOneWidget);
      expect(tester.takeException(), isNull);
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
    // Bounded, not `pumpAndSettle`: the settings page has an always-on animation,
    // so settling here hangs until the 10-minute suite timeout (it did, once).
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }
}
