import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/desktop/desktop_integration_service.dart';
import 'package:mconnect/core/diagnostics/diagnostics_service.dart';
import 'package:mconnect/core/share/deep_link_service.dart';
import 'package:mconnect/features/download/data/repositories/download_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(DesktopIntegrationService.channelName);
  final calls = <MethodCall>[];
  late DesktopIntegrationService service;

  void respondWith(Future<Object?> Function(MethodCall call)? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  /// Pushes a native event into the service, the way the runner does.
  Future<void> emit(String method, [Object? arguments]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          DesktopIntegrationService.channelName,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          (_) {},
        );
  }

  setUp(() {
    calls.clear();
    respondWith((call) async {
      calls.add(call);
      return true;
    });
    service = DesktopIntegrationService();
  });

  tearDown(() {
    service.dispose();
    respondWith(null);
  });

  group('outbound mapping', () {
    test(
      'media metadata goes out as one map with millisecond duration',
      () async {
        await service.setMediaMetadata(
          title: '稻香',
          artist: '周杰伦',
          album: '魔杰座',
          coverUrl: 'https://example.test/cover.jpg',
          durationMs: 223000,
        );

        expect(calls.single.method, 'setMediaMetadata');
        expect(calls.single.arguments, {
          'title': '稻香',
          'artist': '周杰伦',
          'album': '魔杰座',
          'coverUrl': 'https://example.test/cover.jpg',
          'durationMs': 223000,
        });
      },
    );

    test('playback state uses the wire words from the protocol doc', () async {
      await service.setPlaybackState(DesktopPlaybackStatus.playing);
      await service.setPlaybackState(DesktopPlaybackStatus.paused);
      await service.setPlaybackState(DesktopPlaybackStatus.stopped);

      expect(calls.map((call) => call.arguments), [
        {'status': 'playing'},
        {'status': 'paused'},
        {'status': 'stopped'},
      ]);
    });

    test('timeline carries position, duration and the seeking flag', () async {
      await service.setTimeline(positionMs: 42000, durationMs: 223000);
      await service.setTimeline(
        positionMs: 1000,
        durationMs: 223000,
        seeking: true,
      );

      expect(calls.first.arguments, {
        'positionMs': 42000,
        'durationMs': 223000,
        'seeking': false,
      });
      expect((calls.last.arguments as Map)['seeking'], isTrue);
    });

    test('tray state carries every flag the tray icon draws', () async {
      await service.setTrayState(
        playing: true,
        hasSong: true,
        floatingLyrics: false,
        taskbarLyrics: true,
        liked: false,
        title: '稻香',
        artist: '周杰伦',
      );

      expect(calls.single.arguments, {
        'playing': true,
        'hasSong': true,
        'floatingLyrics': false,
        'taskbarLyrics': true,
        'liked': false,
        'title': '稻香',
        'artist': '周杰伦',
      });
    });

    test(
      'freeSpaceBytes answers the byte count the native side measured',
      () async {
        respondWith((call) async {
          calls.add(call);
          return 1234567890;
        });

        expect(await service.freeSpaceBytes(r'D:\Music'), 1234567890);
        expect(calls.single.method, 'freeSpaceBytes');
        expect(calls.single.arguments, r'D:\Music');
      },
    );
  });

  group('desktop behaviour commands (protocol §4.3)', () {
    test('close behaviour carries every switch, including window memory', () async {
      await service.setCloseBehavior(
        minimizeToTray: true,
        firstRunHint: false,
        rememberWindowState: false,
      );

      expect(calls.single.method, 'setCloseBehavior');
      expect(calls.single.arguments, {
        'minimizeToTray': true,
        'firstRunHint': false,
        // The runner owns the save points, so the remember switch has to
        // travel with the close behaviour instead of staying Dart-only.
        'rememberWindowState': false,
      });
    });

    test('hotkeys ship the enabled flag and both chords', () async {
      await service.setHotkeys(
        enabled: true,
        lyricsToggle: 'Ctrl+Alt+L',
        playPause: 'Ctrl+Alt+Space',
      );

      expect(calls.single.method, 'setHotkeys');
      expect(calls.single.arguments, {
        'enabled': true,
        'lyricsToggle': 'Ctrl+Alt+L',
        'playPause': 'Ctrl+Alt+Space',
      });
    });

    test('prevent-sleep is a bare bool, not an envelope', () async {
      // §4.3 pins the parameter type to bool. Sending {'enabled': true} would
      // make a strict runner answer false on every play.
      await service.setPreventSleep(true);
      await service.setPreventSleep(false);

      expect(calls.map((call) => call.arguments), [true, false]);
    });

    test('window state answers the geometry the runner kept', () async {
      respondWith((call) async {
        calls.add(call);
        return <String, Object?>{
          'left': 120,
          'top': 64,
          'width': 1280,
          'height': 800,
          'maximized': false,
        };
      });

      expect(await service.getWindowState(), {
        'left': 120,
        'top': 64,
        'width': 1280,
        'height': 800,
        'maximized': false,
      });
      expect(calls.single.method, 'getWindowState');
      expect(calls.single.arguments, isNull);
    });

    test('a non-map window state is unknown, not an exception', () async {
      respondWith((call) async => 'not-a-map');

      expect(await service.getWindowState(), isNull);
    });

    test('getRuntimeStatus asks the runner instead of waiting', () async {
      respondWith((call) async {
        calls.add(call);
        return <String, Object?>{
          'trayAdded': false,
          'trayError': 5,
          'smtcAvailable': true,
          'hotkeysEnabled': false,
        };
      });

      expect(await service.getRuntimeStatus(), {
        'trayAdded': false,
        'trayError': 5,
        'smtcAvailable': true,
        'hotkeysEnabled': false,
      });
      expect(calls.single.method, 'getRuntimeStatus');
      // No parameters: the runner reads its own state.
      expect(calls.single.arguments, isNull);
    });

    test('a non-map runtime status is unknown, not an exception', () async {
      respondWith((call) async => 'nope');
      expect(await service.getRuntimeStatus(), isNull);
    });

    test('save and reset window state map through', () async {
      await service.saveWindowState({'width': 1024, 'height': 720});
      expect(calls.last.method, 'saveWindowState');
      expect(calls.last.arguments, {'width': 1024, 'height': 720});

      // The protocol's saveWindowState takes no parameters, and a runner that
      // owns the window is the better source of truth for its own rectangle.
      await service.saveWindowState();
      expect(calls.last.arguments, isNull);

      expect(await service.resetWindowState(), isTrue);
      expect(calls.last.method, 'resetWindowState');
      expect(calls.last.arguments, isNull);
    });

    test('takeInitialUri trims the launch link and refuses blanks', () async {
      respondWith((call) async {
        calls.add(call);
        return switch (call.method) {
          'takeInitialUri' => '  mconnect://song/42  ',
          _ => null,
        };
      });
      expect(await service.takeInitialUri(), 'mconnect://song/42');

      respondWith((call) async => '   ');
      expect(await service.takeInitialUri(), isNull);

      respondWith((call) async => 42);
      expect(await service.takeInitialUri(), isNull);
    });

    test('the accent colour is an ARGB int, or unknown', () async {
      respondWith((call) async => 0xFF4F8CFF);
      expect(await service.getAccentColor(), 0xFF4F8CFF);

      // The standard codec widens a large int to double on some paths.
      respondWith((call) async => 4283407615.0);
      expect(await service.getAccentColor(), 4283407615);

      respondWith((call) async => 'blue');
      expect(await service.getAccentColor(), isNull);
    });
  });

  group('no native implementation', () {
    test('every call is a silent false instead of an exception', () async {
      respondWith(null);

      expect(await service.initialize(), isFalse);
      expect(await service.setMediaMetadata(title: 'x'), isFalse);
      expect(
        await service.setPlaybackState(DesktopPlaybackStatus.paused),
        isFalse,
      );
      expect(await service.setTimeline(positionMs: 1, durationMs: 2), isFalse);
      expect(
        await service.setTrayState(
          playing: false,
          hasSong: false,
          floatingLyrics: false,
          taskbarLyrics: false,
          liked: false,
        ),
        isFalse,
      );
      expect(await service.freeSpaceBytes(r'D:\Music'), isNull);
      expect(
        await service.setCloseBehavior(
          minimizeToTray: true,
          firstRunHint: true,
          rememberWindowState: true,
        ),
        isFalse,
      );
      expect(
        await service.setHotkeys(
          enabled: false,
          lyricsToggle: 'Ctrl+Alt+L',
          playPause: 'Ctrl+Alt+Space',
        ),
        isFalse,
      );
      expect(await service.setPreventSleep(true), isFalse);
      expect(await service.getWindowState(), isNull);
      expect(await service.saveWindowState(), isFalse);
      expect(await service.saveWindowState({'width': 800}), isFalse);
      expect(await service.resetWindowState(), isFalse);
      expect(await service.takeInitialUri(), isNull);
      expect(await service.getAccentColor(), isNull);
      expect(await service.getRuntimeStatus(), isNull);
    });

    test('a native failure is reported as false, not thrown', () async {
      respondWith((call) async {
        throw PlatformException(code: 'SMTC_UNAVAILABLE', message: 'no SMTC');
      });

      expect(
        await service.setPlaybackState(DesktopPlaybackStatus.playing),
        isFalse,
      );
      expect(await service.freeSpaceBytes(r'D:\Music'), isNull);
      expect(await service.getWindowState(), isNull);
      expect(await service.getAccentColor(), isNull);
      expect(await service.takeInitialUri(), isNull);
    });
  });

  group('inbound events', () {
    test(
      'smtcControl reaches the stream with its action and position',
      () async {
        final events = <DesktopIntegrationEvent>[];
        final sub = service.events.listen(events.add);
        addTearDown(sub.cancel);

        await emit('smtcControl', {'action': 'seek', 'positionMs': 42000});
        await pumpEventQueue();

        expect(events.single.name, 'smtcControl');
        expect(events.single['action'], 'seek');
        expect(events.single['positionMs'], 42000);
      },
    );

    test('a malformed event is dropped instead of throwing', () async {
      final events = <DesktopIntegrationEvent>[];
      final sub = service.events.listen(events.add);
      addTearDown(sub.cancel);

      await emit('trayCommand', 'not-a-map');
      await emit('trayCommand');
      await pumpEventQueue();

      expect(events.where((event) => event.name == 'trayCommand'), isEmpty);
    });

    test('tray failures and the minimized fallback reach the stream', () async {
      final events = <DesktopIntegrationEvent>[];
      final sub = service.events.listen(events.add);
      addTearDown(sub.cancel);

      await emit('trayFailed', {'error': 5, 'stage': 'add'});
      await emit('minimizedInsteadOfTray', {'reason': 5});
      await pumpEventQueue();

      expect(events.map((event) => event.name), [
        'trayFailed',
        'minimizedInsteadOfTray',
      ]);
      expect(events.first['error'], 5);
      expect(events.first['stage'], 'add');
      expect(events.last['reason'], 5);
    });

    test('only the documented event names are forwarded', () async {
      final events = <DesktopIntegrationEvent>[];
      final sub = service.events.listen(events.add);
      addTearDown(sub.cancel);

      await emit('somethingElse', {'a': 1});
      await emit('trayReady', <String, Object?>{});
      // The two close-path answers are part of the protocol now: dropping them
      // would leave the settings page unable to say what the tray really did.
      await emit('hiddenToTray', <String, Object?>{});
      await emit('closeFellBackToExit', <String, Object?>{});
      await pumpEventQueue();

      expect(events.map((event) => event.name), [
        'trayReady',
        'hiddenToTray',
        'closeFellBackToExit',
      ]);
    });
  });

  group('download free-space probe on Windows', () {
    tearDown(() => debugWindowsFreeSpaceProbe = null);

    test('an injected probe wins over the channel', () async {
      debugWindowsFreeSpaceProbe = (path) async => 9000;

      expect(await windowsFreeSpaceProbeForTest(r'D:\Music'), 9000);
    });

    test('the production path reads freeSpaceBytes from the runner', () async {
      respondWith((call) async => 555000000);

      expect(await windowsFreeSpaceProbeForTest(r'D:\Music'), 555000000);
    });

    test('no runner means unknown, never zero', () async {
      respondWith(null);

      expect(await windowsFreeSpaceProbeForTest(r'D:\Music'), isNull);
    });
  });

  group('deep-link bridge', () {
    test('the runner launch URI wins over the platform initial link', () async {
      respondWith(
        (call) async =>
            call.method == 'takeInitialUri' ? 'mconnect://song/42' : null,
      );
      final source = DesktopLinkSource(
        desktop: service,
        fallback: _FakeLinkSource(initial: Uri.parse('mconnect://song/1')),
      );

      expect((await source.initialLink()).toString(), 'mconnect://song/42');
    });

    test(
      'with no URI from the runner the platform source still answers',
      () async {
        respondWith((call) async => null);
        final source = DesktopLinkSource(
          desktop: service,
          fallback: _FakeLinkSource(initial: Uri.parse('mconnect://song/1')),
        );

        expect((await source.initialLink()).toString(), 'mconnect://song/1');
      },
    );

    test('uriReceived events reach the deep-link stream', () async {
      final source = DesktopLinkSource(
        desktop: service,
        fallback: _FakeLinkSource(),
      );
      final uris = <Uri>[];
      final sub = source.links().listen(uris.add);
      addTearDown(sub.cancel);

      await emit('uriReceived', {'uri': 'mconnect://song/7'});
      await emit('uriReceived', {'uri': '  '});
      await emit('trayCommand', {'action': 'toggleLyrics'});
      await pumpEventQueue();

      expect(uris.map((uri) => uri.toString()), ['mconnect://song/7']);
    });
  });

  // Last group on purpose: it initialises the process-wide DiagnosticsService
  // and resets it again, so nothing after it may depend on the singleton.
  group('diagnostics stay one-shot per method', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mconnect_desktop_diag_');
      await DiagnosticsService.instance.initializeForTest(tempDir);
      respondWith(null);
      service = DesktopIntegrationService();
    });

    tearDown(() async {
      await DiagnosticsService.instance.flush();
      await DiagnosticsService.instance.resetForTest();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'a missing handler costs one log line per method, not one per call',
      () async {
        for (var i = 0; i < 3; i++) {
          await service.setPreventSleep(true);
          await service.getWindowState();
          await service.getAccentColor();
          await service.takeInitialUri();
          await service.resetWindowState();
        }

        final unavailable = DiagnosticsService.instance.recentEvents
            .where(
              (event) =>
                  event.message.contains('desktop_integration_unavailable'),
            )
            .toList();

        expect(unavailable, hasLength(5));
        expect(
          unavailable.where(
            (event) => event.message.contains('setPreventSleep'),
          ),
          hasLength(1),
        );
        expect(
          unavailable.where(
            (event) => event.message.contains('getWindowState'),
          ),
          hasLength(1),
        );
      },
    );
  });
}

/// Minimal [LinkSource] for the bridge tests: the app-links plugin never answers
/// in a test process, and the bridge's job is precisely to decide which source
/// wins.
class _FakeLinkSource implements LinkSource {
  _FakeLinkSource({this.initial});

  final Uri? initial;

  @override
  Future<Uri?> initialLink() async => initial;

  @override
  Stream<Uri> links() => const Stream<Uri>.empty();
}