import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mconnect/features/floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import 'package:mconnect/features/player/presentation/providers/lyrics_provider.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

import 'support/content_page_fakes.dart';

/// Regression guard for v1.4.2's "floating lyrics disappear forever".
///
/// The native side gated window creation on `hiddenByUser`, a latch only its
/// `show()` could clear — and Dart never calls `show()`. Since Dart calls
/// `hide()` whenever the feature is off (the default state), the latch was
/// closed almost immediately and the overlay could never come back.
///
/// The Kotlin half is a compile-time-only change (this environment cannot run
/// Android code), so what is pinned here is the **Dart half of the contract**:
/// after a close, re-enabling the feature must send another `update` — that is
/// the call the native side now honours by clearing the flag and creating the
/// window.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late List<MethodCall> calls;

  const channel = MethodChannel('com.mconnect.mconnect/floating_lyrics');

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mconnect_floating_regress_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    calls = <MethodCall>[];
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  void mockChannel({Duration? hideDelay}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'canDrawOverlays' => true,
            'hide' => hideDelay == null
                ? true
                : await Future<bool>.delayed(hideDelay, () => true),
            'update' => true,
            'show' => true,
            _ => null,
          };
        });
  }

  ProviderContainer buildContainer({bool playing = false}) {
    final player = _TestPlayerNotifier(playing: playing);
    final container = ProviderContainer(
      overrides: [
        playerProvider.overrideWith((ref) => player),
        lyricsProvider.overrideWith((ref) async => _document),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  List<String> methodsSinceLastHide() {
    final lastHide = calls.lastIndexWhere((call) => call.method == 'hide');
    final from = lastHide < 0 ? 0 : lastHide + 1;
    return calls.skip(from).map((call) => call.method).toList();
  }

  test(
    're-enabling the overlay after a close must send another update',
    () async {
      mockChannel();
      final container = buildContainer();
      await container.read(lyricsProvider.future);
      container.read(floatingLyricsSyncProvider);
      final notifier = container.read(floatingLyricsProvider.notifier);

      // Default state: the feature is off, so sync() hides the overlay. This is
      // what closed the v1.4.2 latch in normal use.
      await notifier.setEnabled(true);
      await pumpEventQueue();
      expect(
        calls.map((call) => call.method),
        contains('update'),
        reason: '开启后必须推送一次 update（原生据此创建窗口）',
      );

      await notifier.setEnabled(false);
      await pumpEventQueue();
      expect(calls.map((call) => call.method), contains('hide'));

      // ...and turning it back on must ask for the window again.
      await notifier.setEnabled(true);
      await pumpEventQueue();

      expect(
        methodsSinceLastHide(),
        contains('update'),
        reason: '回到开启状态后必须再次 update —— 否则窗口（在修复前的原生闩锁下）永不重建，'
            '这正是 v1.4.2 用户看到的"悬浮歌词彻底消失"',
      );
    },
  );

  test(
    'closing from the overlay stops the sweep, so no update re-creates it',
    () async {
      // A slow hide widens the window between "user closed it" and
      // "setEnabled(false) landed": long enough for a 200ms sweep tick to fire
      // if the timer were still running.
      mockChannel(hideDelay: const Duration(milliseconds: 400));
      final container = buildContainer(playing: true);
      await container.read(lyricsProvider.future);
      container.read(floatingLyricsSyncProvider);
      final notifier = container.read(floatingLyricsProvider.notifier);

      await notifier.setEnabled(true);
      await pumpEventQueue();
      final updatesBeforeClose = calls
          .where((call) => call.method == 'update')
          .length;
      expect(updatesBeforeClose, greaterThan(0));

      await _sendNativeCall('closedByUser');
      // Wait past the delayed hide AND past two sweep intervals.
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(
        calls.where((call) => call.method == 'update').length,
        updatesBeforeClose,
        reason: '用户关闭后不得再有任何 update：否则原生会把刚关掉的窗口重建回来（addView/removeView 抖动）',
      );
      expect(notifier.state.enabled, isFalse);
      expect(calls.map((call) => call.method), contains('hide'));
    },
  );
}

Future<void> _sendNativeCall(String method, [Object? arguments]) {
  const codec = StandardMethodCodec();
  return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'com.mconnect.mconnect/floating_lyrics',
        codec.encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
}

const _song = Song(
  id: 'regression-song',
  platform: PlatformType.netease,
  name: 'Regression Song',
  artists: [Artist(id: 'artist', name: 'Artist')],
);

const _document = LyricsDocument(
  lines: [
    LyricsLine(timestamp: Duration.zero, text: 'Playing lyric line'),
    LyricsLine(timestamp: Duration(seconds: 10), text: 'Next lyric line'),
  ],
);

/// A player whose transport state the test controls.
///
/// The main regression case is deliberately **paused**: while playing, the
/// 200 ms sweep keeps advancing the interpolated position, so *some* update is
/// emitted eventually no matter what the signature cache does — the sweep would
/// hide the very bug the test exists to catch.
class _TestPlayerNotifier extends PlayerNotifier {
  _TestPlayerNotifier({bool playing = false})
    : super(
        audioController: IdleAudioController(),
        audioControllerFactory: IdleAudioController.new,
      ) {
    state = state.copyWith(
      currentSong: _song,
      playlist: const [_song],
      currentIndex: 0,
      position: Duration.zero,
      duration: const Duration(minutes: 3),
      isPlaying: playing,
    );
  }
}
