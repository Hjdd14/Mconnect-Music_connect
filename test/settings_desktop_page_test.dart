import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/desktop/desktop_behavior_settings.dart';
import 'package:mconnect/core/desktop/desktop_integration_service.dart';
import 'package:go_router/go_router.dart';
import 'package:mconnect/features/settings/presentation/desktop/settings_desktop_page.dart';
import 'package:mconnect/features/settings/presentation/pages/settings_page.dart';
import 'package:mconnect/features/settings/presentation/widgets/lyrics_studio/lyrics_studio.dart';

/// The desktop settings page's 桌面行为 section.
///
/// The section is pumped on its own for most cases: the full page builds the
/// lyrics studio first, whose preview ticker makes every unrelated assertion
/// slower than it needs to be. One case does go through the real page, because
/// "the section is reachable from the sidebar" is itself part of the wiring.
///
/// The store is the memory seam (real Hive writes from a UI callback leave a
/// continuation behind in FakeAsync and hang the file-level Hive.close — see
/// test/settings_persistence_test.dart); "it really persists" is covered by
/// test/desktop_behavior_settings_test.dart over the Hive store.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(DesktopIntegrationService.channelName);
  final calls = <MethodCall>[];
  late Directory tempDir;
  late MemoryDesktopBehaviorSettingsStore store;
  late DesktopIntegrationService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_desktop_page_');
    Hive.init(tempDir.path);
    await Hive.openBox(desktopBehaviorBoxName);
    store = MemoryDesktopBehaviorSettingsStore();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
    service = DesktopIntegrationService();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await service.dispose();
    try {
      await Hive.close().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Bounded: a wedged close must not drag the suite down.
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [
        desktopBehaviorSettingsStoreProvider.overrideWithValue(store),
        desktopIntegrationServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  /// The section is taller than the default 800x600 test surface; a tall view
  /// keeps every switch and field hit-testable without scrolling in each case.
  void useTallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('the section renders the persisted values', (tester) async {
    useTallView(tester);
    store = MemoryDesktopBehaviorSettingsStore({
      'closeToTray': false,
      'hotkeysEnabled': true,
      'toggleLyricsHotkey': 'Ctrl+Shift+K',
    });

    await tester.pumpWidget(
      wrap(
        const SingleChildScrollView(child: DesktopBehaviorSettingsSection()),
      ),
    );
    await tester.pump();

    expect(find.text('关闭到托盘'), findsOneWidget);
    expect(find.text('播放时防止休眠'), findsOneWidget);
    expect(find.text('Ctrl+Shift+K'), findsOneWidget);

    final closeSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('desktop-close-to-tray')),
    );
    expect(closeSwitch.value, isFalse);
    final hotkeySwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('desktop-hotkeys-enabled')),
    );
    expect(hotkeySwitch.value, isTrue);
  });

  testWidgets('every switch asks the store for a save', (tester) async {
    useTallView(tester);

    await tester.pumpWidget(
      wrap(
        const SingleChildScrollView(child: DesktopBehaviorSettingsSection()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('desktop-close-to-tray')));
    await tester.pump();
    expect(store.writes.last['closeToTray'], isFalse);

    await tester.tap(find.byKey(const Key('desktop-first-run-hint')));
    await tester.pump();
    expect(store.writes.last['firstRunHint'], isFalse);

    await tester.tap(find.byKey(const Key('desktop-remember-window')));
    await tester.pump();
    expect(store.writes.last['rememberWindowState'], isFalse);

    await tester.tap(find.byKey(const Key('desktop-prevent-sleep')));
    await tester.pump();
    expect(store.writes.last['preventSleepWhilePlaying'], isTrue);
  });

  testWidgets('a typed hotkey is saved on submit, not per keystroke', (
    tester,
  ) async {
    useTallView(tester);

    await tester.pumpWidget(
      wrap(
        const SingleChildScrollView(child: DesktopBehaviorSettingsSection()),
      ),
    );
    await tester.pump();

    // The fields are disabled until the feature switch is on.
    await tester.tap(find.byKey(const Key('desktop-hotkeys-enabled')));
    await tester.pump();
    expect(store.writes, hasLength(1));

    await tester.enterText(
      find.byKey(const Key('desktop-hotkey-toggle-lyrics')),
      'Ctrl+Shift+K',
    );
    await tester.pump();
    expect(
      store.writes,
      hasLength(1),
      reason: 'typing must not write on every character',
    );

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(store.writes.last['toggleLyricsHotkey'], 'Ctrl+Shift+K');
    expect(store.writes.last['hotkeysEnabled'], isTrue);
  });

  testWidgets('reset asks the runner and reports the answer', (tester) async {
    useTallView(tester);

    await tester.pumpWidget(
      wrap(
        const SingleChildScrollView(child: DesktopBehaviorSettingsSection()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('desktop-reset-window')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(calls.map((call) => call.method), contains('resetWindowState'));
    expect(find.text('窗口状态已重置'), findsOneWidget);
  });

  /// A router-backed harness for the whole page.
  ///
  /// The page derives its section from `?section=`, so pumping it outside a
  /// GoRouter has no location to read -- and asserting the URL is the point:
  /// the sidebar chip links to `/settings?section=accounts`, which is exactly
  /// the parameter the page used to ignore.
  Widget wrapRouter(GoRouter router) {
    return ProviderScope(
      overrides: [
        desktopBehaviorSettingsStoreProvider.overrideWithValue(store),
        desktopIntegrationServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  GoRouter settingsRouter(String location) {
    return GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsDesktopPage(),
        ),
      ],
    );
  }

  testWidgets('?section=accounts lands on the account rows, not the lyrics studio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = settingsRouter('/settings?section=accounts');
    addTearDown(router.dispose);

    await tester.pumpWidget(wrapRouter(router));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsAccountsPage), findsOneWidget);
    // The old page showed one 「打开账号管理」 card and pushed a second screen;
    // the rows themselves are here now.
    expect(find.text('打开账号管理'), findsNothing);
    expect(find.byType(LyricsStudio), findsNothing);
  });

  testWidgets('settings without a section defaults to accounts', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = settingsRouter('/settings');
    addTearDown(router.dispose);

    await tester.pumpWidget(wrapRouter(router));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsAccountsPage), findsOneWidget);
  });

  testWidgets('an unknown section falls back to accounts', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = settingsRouter('/settings?section=does-not-exist');
    addTearDown(router.dispose);

    await tester.pumpWidget(wrapRouter(router));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsAccountsPage), findsOneWidget);
  });

  testWidgets('picking 播放 shows the playback half, not the equalizer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = settingsRouter('/settings');
    addTearDown(router.dispose);

    await tester.pumpWidget(wrapRouter(router));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-section-playback')));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.query, 'section=playback');
    final audioPage = tester.widget<SettingsAudioPage>(
      find.byType(SettingsAudioPage),
    );
    expect(audioPage.section, SettingsAudioSection.playback);
    expect(find.text('淡入淡出'), findsOneWidget);
  });

  testWidgets('the settings page reaches the 桌面行为 section', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = settingsRouter('/settings?section=desktop');
    addTearDown(router.dispose);

    await tester.pumpWidget(wrapRouter(router));
    await tester.pumpAndSettle();

    expect(find.text('关闭到托盘'), findsOneWidget);
    expect(find.text('重置窗口状态'), findsOneWidget);
    // The switches alone cannot say whether the runner agreed; the status
    // card is what turns a silently dead tray/hotkey into a visible answer.
    expect(find.text('运行状态'), findsOneWidget);
  });
}
