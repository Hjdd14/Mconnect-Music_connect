import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/lyrics/lyrics_animation_catalog.dart';
import 'package:mconnect/core/lyrics/lyrics_overlay_config.dart';
import 'package:mconnect/features/floating_lyrics/data/floating_lyrics_models.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/taskbar_lyrics_provider.dart';
import 'package:mconnect/features/settings/presentation/widgets/lyrics_studio/lyrics_studio.dart';
import 'package:mconnect/features/settings/presentation/widgets/lyrics_studio/lyrics_studio_controller.dart';

/// Widget-level guard for the embeddable lyrics studio: it must render a live
/// preview, switch surfaces, expose the geometry controls both native windows
/// actually read, and write every change through the persisted notifiers
/// (settings_page.dart itself is out of this task's scope).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_lyrics_studio_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget wrap({TaskbarLyricsStatus? taskbarStatus}) {
    return ProviderScope(
      overrides: <Override>[
        floatingLyricsProvider.overrideWith((ref) => _MemoryFloatingNotifier()),
        taskbarLyricsProvider.overrideWith((ref) => _MemoryTaskbarNotifier()),
        // The status provider is the one place that probes the native taskbar
        // geometry, so the widget tests stub it instead of touching a channel.
        taskbarLyricsStatusProvider.overrideWith(
          (ref) => TaskbarLyricsStatusNotifier(
            initial: taskbarStatus ?? const TaskbarLyricsStatus(),
          ),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LyricsStudio(
              autoPlayPreview: false,
              nativePreview: _noopNativePreview,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders the studio and a live preview', (tester) async {
    await _pumpStudio(tester, wrap());

    expect(find.byKey(const Key('lyrics-studio')), findsOneWidget);
    expect(find.text('歌词工作室'), findsOneWidget);
    expect(find.byKey(const Key('lyrics-studio-preview')), findsOneWidget);
    // The first sample line is painted by the Flutter preview.
    expect(find.text('夜色渐浓，城市在窗外后退'), findsWidgets);
    // Both surfaces are offered.
    expect(find.text('悬浮歌词'), findsOneWidget);
    expect(find.text('任务栏歌词'), findsOneWidget);
    // The line picker offers every floating animation.
    expect(
      find.byKey(const ValueKey<String>('lyrics-line-animation-flipY')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('lyrics-window-animation-pop')),
      findsOneWidget,
    );
  });

  testWidgets('switching to the taskbar previews its own defaults', (
    tester,
  ) async {
    await _pumpStudio(tester, wrap());

    await tester.tap(find.text('任务栏歌词'));
    await tester.pumpAndSettle();

    final chip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey<String>('lyrics-line-animation-slideLeft')),
    );
    expect(chip.selected, isTrue);
    // Floating-only animation is not offered on the strip.
    expect(
      find.byKey(const ValueKey<String>('lyrics-line-animation-flipY')),
      findsNothing,
    );
    // The taskbar default 200 ms is offered.
    expect(
      find.byKey(const ValueKey<String>('lyrics-studio-duration-200')),
      findsOneWidget,
    );
    // Reduce motion is a shared behaviour switch, so both surfaces show it.
    expect(
      find.byKey(const Key('lyrics-studio-reduce-motion')),
      findsOneWidget,
    );
  });

  testWidgets('the floating surface exposes size, position and monitor', (
    tester,
  ) async {
    await _pumpStudio(tester, wrap());

    for (final key in <String>[
      'lyrics-studio-width',
      'lyrics-studio-height',
      'lyrics-studio-position-x',
      'lyrics-studio-position-y-ratio',
      'lyrics-studio-monitor',
      'lyrics-studio-font-weight',
      'lyrics-studio-line-height',
      'lyrics-studio-letter-spacing',
      'lyrics-studio-padding',
      'lyrics-studio-stroke-width',
      'lyrics-studio-shadow-opacity',
      'lyrics-studio-show-translation',
      'lyrics-studio-click-through',
      'lyrics-studio-always-on-top',
      'lyrics-studio-show-controls',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
  });

  testWidgets('the floating geometry sliders write through the notifier', (
    tester,
  ) async {
    await _pumpStudio(tester, wrap());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LyricsStudio)),
    );

    _dragSlider(tester, 'lyrics-studio-width', 480);
    await _pumpInteraction(tester);
    expect(container.read(floatingLyricsProvider).width, 480);

    _dragSlider(tester, 'lyrics-studio-height', 140);
    await _pumpInteraction(tester);
    expect(container.read(floatingLyricsProvider).height, 140);

    _dragSlider(tester, 'lyrics-studio-position-x', 0.25);
    await _pumpInteraction(tester);
    expect(container.read(floatingLyricsProvider).positionX, 0.25);

    _dragSlider(tester, 'lyrics-studio-position-y-ratio', 0.75);
    await _pumpInteraction(tester);
    expect(container.read(floatingLyricsProvider).positionYRatio, 0.75);

    // The centre shortcut snaps the horizontal ratio back to the middle.
    await tester.tap(find.byKey(const Key('lyrics-studio-position-center')));
    await _pumpInteraction(tester);
    expect(container.read(floatingLyricsProvider).positionX, 0.5);
  });

  testWidgets('the taskbar surface exposes geometry, anchor and a status bar', (
    tester,
  ) async {
    await _pumpStudio(tester, wrap());
    await tester.tap(find.text('任务栏歌词'));
    await tester.pumpAndSettle();

    for (final key in <String>[
      'lyrics-studio-monitor',
      'lyrics-studio-anchor',
      'lyrics-studio-offset-x',
      'lyrics-studio-width',
      'lyrics-studio-height',
      'lyrics-studio-edge-padding',
      'lyrics-studio-background-mode',
      'lyrics-studio-translation-layout',
      'lyrics-studio-marquee',
      'lyrics-studio-follow-auto-hide',
      'lyrics-studio-hide-in-fullscreen',
      'lyrics-studio-click-through',
      'lyrics-studio-debug-geometry',
      'lyrics-studio-taskbar-status',
      'lyrics-studio-taskbar-refresh',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }

    // Nothing has been probed yet in this test, so the strip reads as missing.
    expect(find.text('未找到任务栏，已隐藏'), findsOneWidget);
  });

  testWidgets('the taskbar status bar reports the docked edge', (tester) async {
    await _pumpStudio(
      tester,
      wrap(
        taskbarStatus: const TaskbarLyricsStatus(found: true, edge: 'bottom'),
      ),
    );
    await tester.tap(find.text('任务栏歌词'));
    await tester.pumpAndSettle();

    expect(find.text('已停靠：底部'), findsOneWidget);
  });

  testWidgets('the status bar shows the live rectangle the sliders produced', (
    tester,
  ) async {
    await _pumpStudio(
      tester,
      wrap(
        taskbarStatus: const TaskbarLyricsStatus(
          found: true,
          edge: 'bottom',
          placement: Rect.fromLTWH(1200, 1392, 980, 56),
        ),
      ),
    );
    await tester.tap(find.text('任务栏歌词'));
    await tester.pumpAndSettle();

    // This is what turns "the number did nothing" into a checkable fact.
    expect(find.text('已停靠：底部 · 宽 980×56 · 位置 1200,1392'), findsOneWidget);
  });

  testWidgets('a native geometry self-test failure is visible in the status bar', (
    tester,
  ) async {
    await _pumpStudio(
      tester,
      wrap(
        taskbarStatus: const TaskbarLyricsStatus(
          found: true,
          edge: 'bottom',
          lastError: '几何自检失败：a full-width bar at the bottom is a bottom bar',
        ),
      ),
    );
    await tester.tap(find.text('任务栏歌词'));
    await tester.pumpAndSettle();

    // The whole point of moving the self-test into Release: a wrong edge used to
    // be invisible except as "the sliders do nothing".
    expect(
      find.textContaining('几何自检失败'),
      findsOneWidget,
    );
  });

  testWidgets('an insufficient taskbar space is reported as a full-width strip', (
    tester,
  ) async {
    await _pumpStudio(
      tester,
      wrap(
        taskbarStatus: const TaskbarLyricsStatus(
          found: true,
          edge: 'bottom',
          spaceInsufficient: true,
        ),
      ),
    );
    await tester.tap(find.text('任务栏歌词'));
    await tester.pumpAndSettle();

    expect(
      find.text('任务栏应用区已被系统占满，歌词条铺满整条任务栏'),
      findsOneWidget,
    );
  });

  testWidgets('the taskbar anchor, width and offset write through', (
    tester,
  ) async {
    await _pumpStudio(tester, wrap());
    await tester.tap(find.text('任务栏歌词'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LyricsStudio)),
    );

    await tester.tap(find.byKey(const Key('lyrics-studio-anchor')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('靠右').last);
    await tester.pumpAndSettle();
    expect(
      container.read(taskbarLyricsProvider).anchor,
      LyricsTaskbarAnchor.right,
    );

    _dragSlider(tester, 'lyrics-studio-width', 800);
    await _pumpInteraction(tester);
    expect(container.read(taskbarLyricsProvider).width, 800);

    _dragSlider(tester, 'lyrics-studio-offset-x', 120);
    await _pumpInteraction(tester);
    expect(container.read(taskbarLyricsProvider).offsetX, 120);
  });

  testWidgets('picking a line animation updates and persists it', (
    tester,
  ) async {
    await _pumpStudio(tester, wrap());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LyricsStudio)),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('lyrics-line-animation-glowSoft')),
    );
    await _pumpInteraction(tester);

    expect(
      container.read(floatingLyricsProvider).lineAnimation,
      LyricsLineTransition.glowSoft,
    );
    // Persistence of the same setter is covered by
    // test/floating_lyrics_provider_test.dart; here the wiring is what matters.
  });

  testWidgets('picking a taskbar animation writes the taskbar setting', (
    tester,
  ) async {
    await _pumpStudio(tester, wrap());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LyricsStudio)),
    );

    await tester.tap(find.text('任务栏歌词'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('lyrics-line-animation-wipeLeft')),
    );
    await _pumpInteraction(tester);

    expect(
      container.read(taskbarLyricsProvider).lineAnimation,
      LyricsLineTransition.wipeLeft,
    );
    // The floating setting is untouched.
    expect(
      container.read(floatingLyricsProvider).lineAnimation,
      LyricsLineTransition.fade,
    );
  });

  testWidgets('replay bumps the preview token', (tester) async {
    await _pumpStudio(tester, wrap());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LyricsStudio)),
    );
    final before = container.read(lyricsStudioProvider).previewToken;

    await tester.tap(find.byKey(const Key('lyrics-studio-replay')));
    await tester.pumpAndSettle();

    expect(container.read(lyricsStudioProvider).previewToken, before + 1);
  });

  testWidgets('the enable switch persists the floating window', (tester) async {
    await _pumpStudio(tester, wrap());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LyricsStudio)),
    );

    expect(container.read(floatingLyricsProvider).enabled, isFalse);
    await tester.tap(find.byKey(const Key('lyrics-studio-enabled')));
    await _pumpInteraction(tester);

    expect(container.read(floatingLyricsProvider).enabled, isTrue);
  });

  testWidgets('line mode currentOnly drops the translation from the preview', (
    tester,
  ) async {
    await _pumpStudio(tester, wrap());
    const translation = 'The night deepens, the city slips behind';
    expect(find.text(translation), findsOneWidget);

    await tester.tap(find.byKey(const Key('lyrics-studio-line-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅当前行').last);
    await tester.pumpAndSettle();

    expect(find.text(translation), findsNothing);
  });

  testWidgets('reduce motion is off by default and can be turned on', (
    tester,
  ) async {
    await _pumpStudio(tester, wrap());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LyricsStudio)),
    );
    expect(container.read(floatingLyricsProvider).reduceMotion, isFalse);
    expect(find.text(_reduceMotionHint), findsNothing);

    await tester.tap(find.byKey(const Key('lyrics-studio-reduce-motion')));
    await _pumpInteraction(tester);

    expect(container.read(floatingLyricsProvider).reduceMotion, isTrue);
    expect(find.text(_reduceMotionHint), findsOneWidget);
  });

  testWidgets('the reduce-motion hint sits above the animation pickers', (
    tester,
  ) async {
    await _pumpStudio(
      tester,
      wrap(),
      // Start with the flag on: the studio is the screen that has to explain
      // why the animation chooser looks dead.
      floating: const FloatingLyricsSettings(reduceMotion: true),
    );

    expect(find.text(_reduceMotionHint), findsOneWidget);

    final hint = tester.getTopLeft(find.text(_reduceMotionHint)).dy;
    final linePicker = tester
        .getTopLeft(
          find.byKey(const ValueKey<String>('lyrics-line-animation-flipY')),
        )
        .dy;
    final windowPicker = tester
        .getTopLeft(
          find.byKey(const ValueKey<String>('lyrics-window-animation-pop')),
        )
        .dy;
    expect(hint, lessThan(linePicker));
    expect(hint, lessThan(windowPicker));
  });

  testWidgets('the hint offers a one-tap way back to the animations', (
    tester,
  ) async {
    await _pumpStudio(
      tester,
      wrap(),
      floating: const FloatingLyricsSettings(reduceMotion: true),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LyricsStudio)),
    );

    await tester.tap(find.byKey(const Key('lyrics-studio-reduce-motion-off')));
    await _pumpInteraction(tester);

    expect(container.read(floatingLyricsProvider).reduceMotion, isFalse);
    expect(find.text(_reduceMotionHint), findsNothing);
  });

  testWidgets('the taskbar reduce-motion switch writes the strip setting', (
    tester,
  ) async {
    await _pumpStudio(tester, wrap());
    await tester.tap(find.text('任务栏歌词'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LyricsStudio)),
    );

    expect(container.read(taskbarLyricsProvider).reduceMotion, isFalse);
    await tester.tap(find.byKey(const Key('lyrics-studio-reduce-motion')));
    await _pumpInteraction(tester);

    expect(container.read(taskbarLyricsProvider).reduceMotion, isTrue);
    expect(find.text(_reduceMotionHint), findsOneWidget);
  });
}

const String _reduceMotionHint = '当前已开启「减少动态效果」，动画选择不会生效';

/// Pumps the studio on a tall surface so every control is inside the viewport,
/// then settles the first frame.
Future<void> _pumpStudio(
  WidgetTester tester,
  Widget child, {
  FloatingLyricsSettings? floating,
}) async {
  tester.view.physicalSize = const Size(900, 8000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(child);
  await tester.pump();
  if (floating != null) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LyricsStudio)),
    );
    await container
        .read(floatingLyricsProvider.notifier)
        .apply((_) => floating);
    await tester.pump();
  }
}

/// Pumps the material chip/switch/ink animations without pumpAndSettle: the
/// chip ink layer keeps a transient callback alive for a couple of frames, and
/// pumpAndSettle's 100 ms step pattern never observes it settle.
Future<void> _pumpInteraction(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

/// Drives a studio slider through its own callback: a tap lands on the middle
/// of the track and would make the expected value depend on the layout width.
void _dragSlider(WidgetTester tester, String key, double value) {
  final slider = tester.widget<Slider>(find.byKey(Key(key)));
  slider.onChanged!(value);
}

/// In-memory variants: the studio must write through the notifier API, but a
/// widget test cannot drive Hive's real I/O inside its fake-async zone.
class _MemoryFloatingNotifier extends FloatingLyricsNotifier {
  @override
  Future<void> apply(
    FloatingLyricsSettings Function(FloatingLyricsSettings current) change,
  ) async {
    state = change(state);
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    state = state.copyWith(enabled: enabled);
  }
}

class _MemoryTaskbarNotifier extends TaskbarLyricsNotifier {
  @override
  Future<void> apply(
    TaskbarLyricsSettings Function(TaskbarLyricsSettings current) change,
  ) async {
    state = change(state);
  }
}

Future<void> _noopNativePreview(
  LyricsSurface surface,
  LyricsLineTransition animation,
) async {}
