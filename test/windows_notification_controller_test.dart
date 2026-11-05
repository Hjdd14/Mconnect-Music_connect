import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/desktop/desktop_integration_service.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

/// The Windows bridge: `PlaybackNotificationController` -> `desktop_integration`.
///
/// Everything is asserted through the method channel the runner really serves,
/// so the test covers the mapping (which call, with which payload, how often)
/// rather than a mock of it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(DesktopIntegrationService.channelName);
  final calls = <MethodCall>[];
  late WindowsPlaybackNotificationController controller;
  late DesktopIntegrationService service;

  void respondWith(Future<Object?> Function(MethodCall call)? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

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

  MethodCall? lastCall(String method) {
    for (final call in calls.reversed) {
      if (call.method == method) return call;
    }
    return null;
  }

  int countOf(String method) =>
      calls.where((call) => call.method == method).length;

  final actions = _RecordingActions();

  const song = Song(
    id: '187',
    platform: PlatformType.netease,
    name: '稻香',
    artists: [Artist(id: 'a1', name: '周杰伦')],
    duration: Duration(minutes: 3, seconds: 43),
  );

  setUp(() async {
    calls.clear();
    actions.reset();
    respondWith((call) async {
      calls.add(call);
      return true;
    });
    service = DesktopIntegrationService();
    controller = WindowsPlaybackNotificationController(service: service);
    await controller.initialize();
    controller.attach(actions.build());
  });

  tearDown(() async {
    controller.detach();
    await service.dispose();
    respondWith(null);
  });

  void update({
    required bool isPlaying,
    required int positionMs,
    bool liked = false,
    bool lyrics = false,
    Song? currentSong,
  }) {
    controller.update(
      currentSong: currentSong ?? song,
      playlist: [currentSong ?? song],
      currentIndex: 0,
      isCurrentSongLiked: liked,
      isFloatingLyricsEnabled: lyrics,
      isPlaying: isPlaying,
      position: Duration(milliseconds: positionMs),
      duration: const Duration(minutes: 3, seconds: 43),
    );
  }

  test('initialize reaches the runner once', () async {
    expect(countOf('initialize'), 1);
  });

  test(
    'a new song publishes metadata, playback state, timeline and tray',
    () async {
      update(isPlaying: true, positionMs: 0);
      await pumpEventQueue();

      expect(lastCall('setMediaMetadata')?.arguments, {
        'title': '稻香',
        'artist': '周杰伦',
        'durationMs': 223000,
      });
      expect(lastCall('setPlaybackState')?.arguments, {'status': 'playing'});
      expect(lastCall('setTimeline')?.arguments, {
        'positionMs': 0,
        'durationMs': 223000,
        'seeking': false,
      });
      expect(
        lastCall('setTrayState')?.arguments,
        containsPair('hasSong', true),
      );
    },
  );

  test('a position-only tick does not rebuild metadata or the tray', () async {
    update(isPlaying: true, positionMs: 0);
    await pumpEventQueue();
    final metadataCalls = countOf('setMediaMetadata');
    final trayCalls = countOf('setTrayState');

    update(isPlaying: true, positionMs: 2000);
    await pumpEventQueue();

    expect(countOf('setMediaMetadata'), metadataCalls);
    expect(countOf('setTrayState'), trayCalls);
    expect(
      lastCall('setTimeline')?.arguments,
      containsPair('positionMs', 2000),
    );
  });

  test('pausing publishes paused and the tray follows', () async {
    update(isPlaying: true, positionMs: 0);
    await pumpEventQueue();

    update(isPlaying: false, positionMs: 5000);
    await pumpEventQueue();

    expect(lastCall('setPlaybackState')?.arguments, {'status': 'paused'});
    expect(lastCall('setTrayState')?.arguments, containsPair('playing', false));
  });

  test('the liked and floating-lyrics flags reach the tray', () async {
    update(isPlaying: true, positionMs: 0, liked: true, lyrics: true);
    await pumpEventQueue();

    final tray = lastCall('setTrayState')?.arguments as Map;
    expect(tray['liked'], isTrue);
    expect(tray['floatingLyrics'], isTrue);
  });

  test('no current song clears the item and stops the clock', () async {
    update(isPlaying: true, positionMs: 1000);
    await pumpEventQueue();

    controller.update(
      currentSong: null,
      playlist: const [],
      currentIndex: -1,
      isCurrentSongLiked: false,
      isFloatingLyricsEnabled: false,
      isPlaying: false,
      position: Duration.zero,
      duration: Duration.zero,
    );
    await pumpEventQueue();

    expect(lastCall('setPlaybackState')?.arguments, {'status': 'stopped'});
    final tray = lastCall('setTrayState')?.arguments as Map;
    expect(tray['hasSong'], isFalse);
  });

  group('smtcControl', () {
    test('play, pause, next and previous drive the actions', () async {
      await emit('smtcControl', {'action': 'play'});
      await emit('smtcControl', {'action': 'pause'});
      await emit('smtcControl', {'action': 'next'});
      await emit('smtcControl', {'action': 'previous'});
      await pumpEventQueue();

      expect(actions.calls, ['play', 'pause', 'next', 'previous']);
    });

    test('seek carries milliseconds', () async {
      await emit('smtcControl', {'action': 'seek', 'positionMs': 42000});
      await pumpEventQueue();

      expect(actions.calls, ['seek:42000']);
    });

    test('stop pauses, because the app has no stop action', () async {
      await emit('smtcControl', {'action': 'stop'});
      await pumpEventQueue();

      expect(actions.calls, ['pause']);
    });

    test('an unknown action is ignored', () async {
      await emit('smtcControl', {'action': 'teleport'});
      await emit('smtcControl', {'action': 'seek'});
      await pumpEventQueue();

      expect(actions.calls, isEmpty);
    });
  });

  group('trayCommand', () {
    test('play/pause/next/previous and the two toggles are mapped', () async {
      await emit('trayCommand', {'action': 'play'});
      await emit('trayCommand', {'action': 'pause'});
      await emit('trayCommand', {'action': 'next'});
      await emit('trayCommand', {'action': 'previous'});
      await emit('trayCommand', {'action': 'toggleLike'});
      await emit('trayCommand', {'action': 'toggleLyrics'});
      await pumpEventQueue();

      expect(actions.calls, [
        'play',
        'pause',
        'next',
        'previous',
        'like',
        'lyrics',
      ]);
    });

    test('an unknown command is ignored instead of thrown', () async {
      await emit('trayCommand', {'action': 'quit'});
      await pumpEventQueue();

      expect(actions.calls, isEmpty);
    });
  });

  test('a runner without the channel keeps update() quiet', () async {
    controller.detach();
    await service.dispose();
    respondWith(null);
    service = DesktopIntegrationService();
    controller = WindowsPlaybackNotificationController(service: service);
    await controller.initialize();

    update(isPlaying: true, positionMs: 0);
    await pumpEventQueue();

    // Nothing threw, and the controller is still usable.
    update(isPlaying: false, positionMs: 1000);
    await pumpEventQueue();
  });
  group('player_provider factory', () {
    tearDown(() => PlatformUtils.setDebugOverride(null));

    test('Windows gets the desktop bridge, not the no-op', () {
      PlatformUtils.setDebugOverride(AppPlatform.windows);

      expect(
        defaultPlaybackNotificationController(),
        isA<WindowsPlaybackNotificationController>(),
      );
    });

    test('every other platform keeps the no-op', () {
      PlatformUtils.setDebugOverride(AppPlatform.linux);
      expect(
        defaultPlaybackNotificationController(),
        isA<NoopPlaybackNotificationController>(),
      );

      PlatformUtils.setDebugOverride(AppPlatform.macos);
      expect(
        defaultPlaybackNotificationController(),
        isA<NoopPlaybackNotificationController>(),
      );
    });
  });
}

class _RecordingActions {
  final List<String> calls = [];

  void reset() => calls.clear();

  PlaybackNotificationActions build() {
    return PlaybackNotificationActions(
      play: () async => calls.add('play'),
      pause: () async => calls.add('pause'),
      skipToNext: () async => calls.add('next'),
      skipToPrevious: () async => calls.add('previous'),
      seek: (position) async => calls.add('seek:${position.inMilliseconds}'),
      toggleLikeCurrentSong: () async => calls.add('like'),
      toggleFloatingLyrics: () async => calls.add('lyrics'),
    );
  }
}
