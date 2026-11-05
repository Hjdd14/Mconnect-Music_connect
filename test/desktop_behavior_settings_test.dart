import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/core/desktop/desktop_behavior_settings.dart';
import 'package:mconnect/core/desktop/desktop_integration_service.dart';

/// The desktop-behaviour settings: defaults, JSON tolerance, persistence seam
/// and the mapping onto the `desktop_integration` channel.
///
/// Two properties are the point of this file:
///
/// * a switch tap must **ask for a save** (the store receives the full JSON),
///   otherwise "the setting looks applied" is only true until the next launch;
/// * the settings must reach the runner in the exact wire shapes protocol
///   section 4.3 defines (a bare bool for `setPreventSleep`, a map with two
///   chords for `setHotkeys`), because a runner that disagrees answers false
///   and the feature silently does nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(DesktopIntegrationService.channelName);
  final calls = <MethodCall>[];
  late DesktopIntegrationService service;

  void respondWith(Future<Object?> Function(MethodCall call)? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  setUp(() {
    calls.clear();
    respondWith((call) async {
      calls.add(call);
      return true;
    });
    service = DesktopIntegrationService();
  });

  tearDown(() async {
    respondWith(null);
    await service.dispose();
  });

  group('defaults', () {
    test('match the desktop behaviour the doc specifies', () {
      const settings = DesktopBehaviorSettings();

      expect(settings.closeToTray, isTrue);
      expect(settings.firstRunHint, isTrue);
      expect(settings.hotkeysEnabled, isFalse);
      expect(settings.toggleLyricsHotkey, 'Ctrl+Alt+L');
      expect(settings.playPauseHotkey, 'Ctrl+Alt+Space');
      expect(settings.preventSleepWhilePlaying, isFalse);
      expect(settings.rememberWindowState, isTrue);
    });

    test('sleep prevention is a state, not a switch', () {
      const enabled = DesktopBehaviorSettings(preventSleepWhilePlaying: true);
      expect(enabled.shouldPreventSleep(isPlaying: true), isTrue);
      expect(
        enabled.shouldPreventSleep(isPlaying: false),
        isFalse,
        reason: 'a paused player must release the OS sleep request',
      );

      const disabled = DesktopBehaviorSettings();
      expect(disabled.shouldPreventSleep(isPlaying: true), isFalse);
    });
  });

  group('JSON', () {
    test('round trip keeps every field', () {
      const settings = DesktopBehaviorSettings(
        closeToTray: false,
        firstRunHint: false,
        hotkeysEnabled: true,
        toggleLyricsHotkey: 'Ctrl+Shift+K',
        playPauseHotkey: 'Ctrl+Alt+P',
        preventSleepWhilePlaying: true,
        rememberWindowState: false,
      );

      expect(DesktopBehaviorSettings.fromJson(settings.toJson()), settings);
    });

    test('a missing or broken value falls back to the default', () {
      final settings = DesktopBehaviorSettings.fromJson({
        'closeToTray': 'not-a-bool',
        'hotkeysEnabled': 1,
        'toggleLyricsHotkey': 42,
        'rememberWindowState': null,
      });

      expect(settings.closeToTray, isTrue, reason: 'garbage keeps the default');
      expect(settings.hotkeysEnabled, isTrue, reason: '1 reads as true');
      expect(
        settings.toggleLyricsHotkey,
        DesktopBehaviorSettings.defaultToggleLyricsHotkey,
        reason: 'a numeric hotkey is unusable',
      );
      expect(settings.rememberWindowState, isTrue);
    });

    test('a non-map value is the defaults, not an exception', () {
      expect(
        DesktopBehaviorSettings.fromJson(null),
        const DesktopBehaviorSettings(),
      );
      expect(
        DesktopBehaviorSettings.fromJson('nope'),
        const DesktopBehaviorSettings(),
      );
    });

    test(
      'hotkeys are trimmed, blank input falls back, long input is capped',
      () {
        expect(
          DesktopBehaviorSettings.normalizeHotkey(
            '  Ctrl + Alt + L  ',
            fallback: 'FALLBACK',
          ),
          'Ctrl + Alt + L',
        );
        expect(
          DesktopBehaviorSettings.normalizeHotkey('   ', fallback: 'FALLBACK'),
          'FALLBACK',
        );
        expect(
          DesktopBehaviorSettings.normalizeHotkey(null, fallback: 'FALLBACK'),
          'FALLBACK',
        );

        final long = 'Ctrl+' * 40;
        expect(
          DesktopBehaviorSettings.normalizeHotkey(long, fallback: 'FALLBACK'),
          hasLength(DesktopBehaviorSettings.maxHotkeyLength),
        );
      },
    );
  });

  group('notifier', () {
    test('loads what the store already holds', () {
      final store = MemoryDesktopBehaviorSettingsStore({
        'closeToTray': false,
        'hotkeysEnabled': true,
      });
      final notifier = DesktopBehaviorSettingsNotifier(store);
      addTearDown(notifier.dispose);

      expect(notifier.state.closeToTray, isFalse);
      expect(notifier.state.hotkeysEnabled, isTrue);
      expect(notifier.state.firstRunHint, isTrue);
    });

    test('every setter writes the full JSON', () async {
      final store = MemoryDesktopBehaviorSettingsStore();
      final notifier = DesktopBehaviorSettingsNotifier(store);
      addTearDown(notifier.dispose);

      await notifier.setCloseToTray(false);
      await notifier.setHotkeysEnabled(true);
      await notifier.setToggleLyricsHotkey('Ctrl+Shift+L');

      expect(store.writes, hasLength(3));
      expect(store.writes.last['closeToTray'], isFalse);
      expect(store.writes.last['hotkeysEnabled'], isTrue);
      expect(store.writes.last['toggleLyricsHotkey'], 'Ctrl+Shift+L');
      expect(store.writes.last['playPauseHotkey'], 'Ctrl+Alt+Space');
    });

    test('a blank hotkey never reaches the store as an empty string', () async {
      final store = MemoryDesktopBehaviorSettingsStore();
      final notifier = DesktopBehaviorSettingsNotifier(store);
      addTearDown(notifier.dispose);

      await notifier.setToggleLyricsHotkey('   ');

      expect(
        notifier.state.toggleLyricsHotkey,
        DesktopBehaviorSettings.defaultToggleLyricsHotkey,
      );
      expect(
        store.writes.last['toggleLyricsHotkey'],
        DesktopBehaviorSettings.defaultToggleLyricsHotkey,
      );
    });
  });

  group('applying to the runner', () {
    test('close, hotkeys and sleep go out as three calls in order', () async {
      const settings = DesktopBehaviorSettings(
        closeToTray: false,
        firstRunHint: false,
        hotkeysEnabled: true,
        toggleLyricsHotkey: 'Ctrl+Shift+K',
        playPauseHotkey: 'Ctrl+Alt+P',
        preventSleepWhilePlaying: true,
      );

      await settings.applyTo(service, isPlaying: true);

      expect(calls.map((call) => call.method), [
        'setCloseBehavior',
        'setHotkeys',
        'setPreventSleep',
      ]);
      expect(calls[0].arguments, {
        'minimizeToTray': false,
        'firstRunHint': false,
        // The runner owns the save points, so window memory travels with the
        // close behaviour. The default stays on, which is the old behaviour.
        'rememberWindowState': true,
      });
      expect(calls[1].arguments, {
        'enabled': true,
        'lyricsToggle': 'Ctrl+Shift+K',
        'playPause': 'Ctrl+Alt+P',
      });
      expect(calls[2].arguments, true);
    });

    test('pausing releases the sleep request', () async {
      const settings = DesktopBehaviorSettings(preventSleepWhilePlaying: true);

      await settings.applyTo(service, isPlaying: false);

      expect(calls.last.method, 'setPreventSleep');
      expect(calls.last.arguments, false);
    });

    test('a missing native handler makes applyTo finish quietly', () async {
      respondWith(null);

      await const DesktopBehaviorSettings().applyTo(service, isPlaying: true);

      expect(calls, isEmpty);
    });
  });

  // Plain test() on purpose: no FakeAsync, so the real Hive write completes.
  // Without this, "clicking a switch only changes memory" would be the new
  // silent failure the store seam was introduced to prevent.
  group('Hive store', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'mconnect_desktop_behavior_',
      );
      Hive.init(tempDir.path);
      await Hive.openBox(desktopBehaviorBoxName);
    });

    tearDown(() async {
      try {
        await Hive.close().timeout(const Duration(seconds: 3));
      } catch (_) {
        // Bounded: a wedged close must not drag the suite down.
      }
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('writes and reads back through the real box', () async {
      const store = HiveDesktopBehaviorSettingsStore();
      expect(store.read(), isNull);

      final settings = const DesktopBehaviorSettings().copyWith(
        closeToTray: false,
        hotkeysEnabled: true,
        playPauseHotkey: 'Ctrl+Shift+P',
      );
      await store.write(settings.toJson());

      final restored = DesktopBehaviorSettings.fromJson(
        const HiveDesktopBehaviorSettingsStore().read(),
      );
      expect(restored, settings);
    });

    test('a closed box reads as never-saved instead of throwing', () async {
      await Hive.close();
      expect(const HiveDesktopBehaviorSettingsStore().read(), isNull);
    });
  });
}
