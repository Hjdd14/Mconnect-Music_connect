import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/diagnostics/diagnostics_service.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/audio_effects_provider.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/player/data/media_kit_windows_audio_controller.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/data/player_playback_memory_store.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/core/storage/session_storage.dart';
import 'package:mconnect/platform/base/music_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows does not create an Android equalizer', () {
    PlatformUtils.setDebugOverride(AppPlatform.windows);
    addTearDown(() => PlatformUtils.setDebugOverride(null));

    expect(createAndroidEqualizerForPlatform(), isNull);
  });

  test('non-Windows desktop does not create an Android equalizer', () {
    PlatformUtils.setDebugOverride(AppPlatform.linux);
    addTearDown(() => PlatformUtils.setDebugOverride(null));

    expect(createAndroidEqualizerForPlatform(), isNull);
  });

  test(
    'default construction does not eagerly create the audio controller',
    () async {
      var created = 0;
      final notifier = PlayerNotifier(
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () {
          created++;
          return _FakeAudioController();
        },
      );
      addTearDown(notifier.dispose);

      expect(notifier.state.currentSong, isNull);
      expect(created, 0);
    },
  );

  test('Android default audio controller is hosted by AudioService', () {
    final source = File(
      'lib/features/player/presentation/providers/player_provider.dart',
    ).readAsStringSync();

    expect(source, contains('defaultPlayerAudioControllerFactory'));
    expect(source, contains('AudioServicePlayerController.instance'));
    expect(source, contains('PlatformUtils.isAndroid'));
  });

  test('Windows default audio controller uses media_kit backend', () {
    PlatformUtils.setDebugOverride(AppPlatform.windows);
    addTearDown(() => PlatformUtils.setDebugOverride(null));

    expect(
      defaultPlayerAudioControllerFactory(),
      isA<MediaKitWindowsAudioController>(),
    );
  });

  test('Linux desktop keeps the existing just_audio controller', () {
    PlatformUtils.setDebugOverride(AppPlatform.linux);
    addTearDown(() => PlatformUtils.setDebugOverride(null));

    expect(defaultPlayerAudioControllerFactory(), isA<JustAudioController>());
  });

  test(
    'playSong does not keep the audio mutex locked while play future is pending',
    () async {
      final audio = _FakeAudioController();
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () => _FakeAudioController(),
      );
      addTearDown(notifier.dispose);

      final playCall = notifier.playSong(_song('1'));
      await expectLater(
        playCall.timeout(const Duration(milliseconds: 200)),
        completes,
      );
      expect(audio.playCalls, 1);
      expect(notifier.state.isTransitioning, isFalse);

      final seekCall = notifier.seek(const Duration(seconds: 12));
      await expectLater(
        seekCall.timeout(const Duration(milliseconds: 200)),
        completes,
      );
      expect(audio.seekCalls, 1);
    },
  );

  test('playSong recovers when a finite audio operation hangs', () async {
    final hangingAudio = _FakeAudioController(hangOnStop: true);
    var recreated = 0;
    final notifier = PlayerNotifier(
      audioController: hangingAudio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioOperationTimeout: const Duration(milliseconds: 20),
      audioDisposeTimeout: const Duration(milliseconds: 20),
      audioControllerFactory: () {
        recreated++;
        return _FakeAudioController();
      },
    );
    addTearDown(notifier.dispose);

    await expectLater(
      notifier.playSong(_song('2')).timeout(const Duration(milliseconds: 250)),
      completes,
    );

    expect(recreated, greaterThanOrEqualTo(1));
    expect(notifier.state.isTransitioning, isFalse);
  });

  test('togglePlay does not wait for a pending play future', () async {
    final audio = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
    );
    addTearDown(notifier.dispose);

    await expectLater(
      notifier.togglePlay().timeout(const Duration(milliseconds: 200)),
      completes,
    );

    expect(audio.playCalls, 1);
  });

  test(
    'playSong keeps volume unchanged when fade is disabled by default',
    () async {
      final audio = _FakeAudioController();
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () => _FakeAudioController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('fade-disabled'));

      expect(audio.volumeChanges, isEmpty);
    },
  );

  test('fade option ramps volume on play and pause when enabled', () async {
    final audio = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
    );
    addTearDown(notifier.dispose);

    notifier.setFadeOptions(enabled: true, duration: Duration.zero);
    await notifier.playSong(_song('fade-enabled'));
    await pumpEventQueue();
    await notifier.togglePlay();

    expect(audio.volumeChanges, containsAllInOrder([0, 1, 0, 1]));
    expect(audio.pauseCalls, 1);
  });

  test(
    'ignores duplicate completed events while the next song is loading',
    () async {
      final audio = _FakeAudioController();
      final songTwoUrl = Completer<String>();
      final platform = _ControlledUrlPlatform(
        urls: {'transition-2': songTwoUrl.future},
      );
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => platform,
        audioControllerFactory: () => _FakeAudioController(),
      );
      addTearDown(notifier.dispose);

      final playlist = [
        _song('transition-1'),
        _song('transition-2'),
        _song('transition-3'),
      ];
      await notifier.playPlaylist(playlist);
      final nextCall = notifier.skipToNext();
      await pumpEventQueue();
      expect(notifier.state.currentSong?.id, 'transition-2');
      expect(notifier.state.isTransitioning, isTrue);

      audio.emitCompleted();
      songTwoUrl.complete('https://example.test/transition-2-low.mp3');
      await nextCall;
      await pumpEventQueue();

      expect(notifier.state.currentSong?.id, 'transition-2');
      expect(audio.lastUrl, contains('transition-2'));
    },
  );

  test(
    'cancels stale fades so an old pause cannot silence later playback',
    () async {
      final audio = _FakeAudioController();
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () => _FakeAudioController(),
      );
      addTearDown(notifier.dispose);

      notifier.setFadeOptions(
        enabled: true,
        duration: const Duration(milliseconds: 60),
      );
      await notifier.playSong(_song('fade-race-1'));
      final pauseCall = notifier.pause();
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await notifier.playSong(_song('fade-race-2'));
      await pauseCall;
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(audio.lastUrl, contains('fade-race-2'));
      expect(audio.volumeChanges.last, 1);
    },
  );

  // W2-B：用户设置的 fadeDuration 可达 3s，但切歌是高频交互 —— 淡出必须被
  // `PlayerNotifier.switchFadeOutMax`(400ms) 夹住。这条断言不靠注释，直接测耗时。
  test('切歌淡出受 400ms 上限约束（设置 3s 淡入淡出也不拖慢切歌）', () async {
    final audio = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      stuckWatchdogInterval: Duration.zero,
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(notifier.dispose);

    notifier.setFadeOptions(enabled: true, duration: const Duration(seconds: 3));
    await notifier.playSong(_song('fade-cap-1'));
    await pumpEventQueue();

    final watch = Stopwatch()..start();
    await notifier.playSong(_song('fade-cap-2'));
    watch.stop();

    expect(
      watch.elapsed,
      lessThan(const Duration(seconds: 2)),
      reason:
          '切歌淡出必须用 min(fadeDuration, switchFadeOutMax=400ms)；沿用用户设置的 '
          '3s 时这里会花掉约 3s（把 maxDuration 参数去掉这条就会红）',
    );

    // 确定性断言（不靠时钟，复核要求的）：3s 被夹到 400ms → 步进 400 ~/ 6 = 66ms。
    expect(
      notifier.lastSwitchFadeStepDelayForTest,
      const Duration(milliseconds: 66),
      reason: '步进间隔必须来自 min(fadeDuration, 400ms)，而不是 3s/6=500ms',
    );

    // min() 语义：用户设 200ms 时**不能**被抬到 400ms（否则"上限"就变成了"固定值"）。
    notifier.setFadeOptions(
      enabled: true,
      duration: const Duration(milliseconds: 200),
    );
    await notifier.playSong(_song('fade-cap-3'));
    await pumpEventQueue();
    expect(
      notifier.lastSwitchFadeStepDelayForTest,
      const Duration(milliseconds: 33),
      reason: '200ms/6=33ms；若被抬到 400ms 会变成 66ms',
    );
  });

  // Wave 2-B（W2-B）：设置项叫「淡入淡出」，但 playSong 以前在 `_safeStop()` 前
  // 从不做 1→0，所以切歌只有在旧曲被硬停 + 新曲淡入 —— 交接处会截断/爆音。
  test('切歌时先 1→0 淡出再停掉旧曲（W2-B）', () async {
    final audio = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      stuckWatchdogInterval: Duration.zero,
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(notifier.dispose);

    // duration: zero → 淡入淡出各只写一次音量，序列因此完全确定。
    notifier.setFadeOptions(enabled: true, duration: Duration.zero);
    await notifier.playSong(_song('fade-switch-1'));
    await pumpEventQueue();
    await notifier.playSong(_song('fade-switch-2'));
    await pumpEventQueue();

    expect(
      audio.volumeChanges,
      [0, 1, 0, 0, 1],
      reason:
          '切歌必须先写一次 0（淡出旧曲）再 stop/setUrl，然后才是新曲的淡入；'
          '旧实现只有 [0, 1, 0, 1]（没有那次淡出）',
    );
  });

  test('equalizer settings are applied through the audio controller', () async {
    final audio = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      audioOperationTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(notifier.dispose);

    await notifier.applyEqualizerSettings(
      const AudioEffectsSettings(
        equalizerEnabled: true,
        equalizerPreset: EqualizerPreset.rock,
      ),
    );

    expect(audio.equalizerEnabledChanges, [true]);
    expect(audio.equalizerBandGainChanges, [
      const EqualizerBandGain(0, 4),
      const EqualizerBandGain(1, 2),
      const EqualizerBandGain(2, 0),
      const EqualizerBandGain(3, 3),
      const EqualizerBandGain(4, 5),
    ]);
  });

  test(
    'local content uri playback is passed through without file wrapping',
    () async {
      final audio = _FakeAudioController();
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () => _FakeAudioController(),
      );
      addTearDown(notifier.dispose);
      const contentUri = 'content://com.android.providers.media/audio/42';

      await notifier.playSong(_song(contentUri, platform: PlatformType.local));

      expect(audio.lastUrl, contentUri);
    },
  );

  test('playSong clears the loading state when audio reports ready', () async {
    final audio = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('3'));

    expect(notifier.state.isTransitioning, isFalse);
    expect(notifier.state.isPlaying, isTrue);
  });

  test(
    'Android transition keeps playback intent through transient stopped state',
    () async {
      PlatformUtils.setDebugOverride(AppPlatform.android);
      addTearDown(() => PlatformUtils.setDebugOverride(null));
      final audio = _FakeAudioController();
      final nextUrl = Completer<String>();
      final platform = _ControlledUrlPlatform(
        urls: {'transition-next': nextUrl.future},
      );
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => platform,
        audioControllerFactory: () => _FakeAudioController(),
        playbackHealthCheckInterval: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(
        _song('transition-current', duration: const Duration(minutes: 4)),
      );
      final transition = notifier.playSong(
        _song('transition-next', duration: const Duration(minutes: 3)),
      );
      await pumpEventQueue();

      expect(notifier.state.currentSong?.id, 'transition-next');
      expect(notifier.state.isTransitioning, isTrue);
      expect(notifier.state.isPlaying, isTrue);

      audio.emitState(
        playing: false,
        processingState: just_audio.ProcessingState.loading,
      );
      await pumpEventQueue();

      expect(notifier.state.currentSong?.id, 'transition-next');
      expect(notifier.state.isPlaying, isTrue);
      expect(notifier.state.isTransitioning, isTrue);

      nextUrl.complete('https://example.test/transition-next-low.mp3');
      await transition;
    },
  );

  test(
    'Android transition keeps song duration through null and zero stream values',
    () async {
      PlatformUtils.setDebugOverride(AppPlatform.android);
      addTearDown(() => PlatformUtils.setDebugOverride(null));
      final audio = _FakeAudioController();
      final nextUrl = Completer<String>();
      final platform = _ControlledUrlPlatform(
        urls: {'duration-next': nextUrl.future},
      );
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => platform,
        audioControllerFactory: () => _FakeAudioController(),
        playbackHealthCheckInterval: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(
        _song('duration-current', duration: const Duration(minutes: 4)),
      );
      final transition = notifier.playSong(
        _song('duration-next', duration: const Duration(minutes: 3)),
      );
      await pumpEventQueue();

      expect(notifier.state.duration, const Duration(minutes: 3));

      audio.emitDuration(null);
      await pumpEventQueue();
      expect(notifier.state.duration, const Duration(minutes: 3));

      audio.emitDuration(Duration.zero);
      await pumpEventQueue();
      expect(notifier.state.duration, const Duration(minutes: 3));

      nextUrl.complete('https://example.test/duration-next-low.mp3');
      await transition;
    },
  );

  test(
    'explicit pause still clears playback intent after transition guards',
    () async {
      PlatformUtils.setDebugOverride(AppPlatform.android);
      addTearDown(() => PlatformUtils.setDebugOverride(null));
      final audio = _FakeAudioController();
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () => _FakeAudioController(),
        playbackHealthCheckInterval: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('explicit-pause'));
      await notifier.pause();
      audio.emitState(
        playing: false,
        processingState: just_audio.ProcessingState.ready,
      );
      await pumpEventQueue();

      expect(notifier.state.isPlaying, isFalse);
      expect(audio.pauseCalls, 1);
    },
  );

  test(
    'player stream errors clear playback state and expose the error',
    () async {
      final audio = _FakeAudioController();
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () => _FakeAudioController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(
        _song('D:\\Music\\broken.mp3', platform: PlatformType.local),
      );
      audio.emitError(StateError('libmpv missing'));
      await pumpEventQueue();

      expect(notifier.state.isPlaying, isFalse);
      expect(notifier.state.isTransitioning, isFalse);
      expect(notifier.state.error, contains('libmpv missing'));
    },
  );

  test(
    'syncs Android background playback state while playing changes',
    () async {
      final audio = _FakeAudioController();
      final notification = _FakePlaybackNotificationController();
      final keepAlive = _FakePlaybackKeepAliveController();
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () => _FakeAudioController(),
        notificationController: notification,
        keepAliveController: keepAlive,
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('background-sync'));
      await notifier.pause();
      await pumpEventQueue();

      expect(keepAlive.playingStates, [true, false]);
      expect(notification.attached, isTrue);
      expect(notification.updates.last.isPlaying, isFalse);
      expect(notification.updates.last.currentSong?.id, 'background-sync');
    },
  );

  test('reasserts Android background playback while already playing', () async {
    final audio = _FakeAudioController();
    final notification = _FakePlaybackNotificationController();
    final keepAlive = _FakePlaybackKeepAliveController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      notificationController: notification,
      keepAliveController: keepAlive,
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('background-reassert'));
    await notifier.reassertBackgroundPlayback();

    expect(keepAlive.playingStates, [true, true]);
    expect(keepAlive.forceStates, [false, true]);
    expect(notification.updates.last.isPlaying, isTrue);
    expect(notification.updates.last.currentSong?.id, 'background-reassert');
  });

  test(
    'notification lyrics action invokes the injected floating lyrics toggle',
    () async {
      final notification = _FakePlaybackNotificationController();
      var toggleCalls = 0;
      final notifier = PlayerNotifier(
        audioController: _FakeAudioController(),
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () => _FakeAudioController(),
        notificationController: notification,
        keepAliveController: _FakePlaybackKeepAliveController(),
        toggleFloatingLyrics: () async => toggleCalls++,
      );
      addTearDown(notifier.dispose);

      final actions = notification.actions;
      expect(actions, isNotNull);
      await actions!.toggleFloatingLyrics();

      expect(toggleCalls, 1);
    },
  );

  test('dispose detaches notification and releases playback keep alive', () {
    final notification = _FakePlaybackNotificationController();
    final keepAlive = _FakePlaybackKeepAliveController();
    final notifier = PlayerNotifier(
      audioController: _FakeAudioController(),
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      notificationController: notification,
      keepAliveController: keepAlive,
    );

    notifier.dispose();

    expect(notification.detached, isTrue);
    expect(keepAlive.disposed, isTrue);
  });

  test('dispose drops the audio controller reference', () {
    final notifier = PlayerNotifier(
      audioController: _FakeAudioController(),
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );

    expect(notifier.hasAudioControllerForTest, isTrue);

    notifier.dispose();

    // 置空后才不会有遗留回调复用已 dispose 的控制器（复活死掉的平台通道）。
    expect(notifier.hasAudioControllerForTest, isFalse);
  });

  test('playNext inserts the song right after the current one', () async {
    final audio = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(notifier.dispose);

    await notifier.playPlaylist([
      _song('next-a'),
      _song('next-b'),
      _song('next-c'),
    ]);

    notifier.playNext(_song('next-d'));

    expect(
      notifier.state.playlist.map((song) => song.id),
      ['next-a', 'next-d', 'next-b', 'next-c'],
    );
    expect(notifier.state.currentIndex, 0);
    expect(notifier.state.currentSong?.id, 'next-a');

    await notifier.skipToNext();
    expect(notifier.state.currentSong?.id, 'next-d');
  });

  test('playNext does not interrupt the current playback', () async {
    final audio = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(notifier.dispose);

    await notifier.playPlaylist([_song('quiet-a'), _song('quiet-b')]);
    final setUrlCalls = audio.setUrlCalls;
    final playCalls = audio.playCalls;

    notifier.playNext(_song('quiet-c'));

    // 纯队列操作：不取流、不重建播放器、不重播当前曲目。
    expect(audio.setUrlCalls, setUrlCalls);
    expect(audio.playCalls, playCalls);
    expect(notifier.state.currentSong?.id, 'quiet-a');
    expect(notifier.state.isPlaying, isTrue);
  });

  test('playNext moves an already queued song instead of duplicating it', () async {
    final notifier = PlayerNotifier(
      audioController: _FakeAudioController(),
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(notifier.dispose);

    await notifier.playPlaylist([
      _song('dup-a'),
      _song('dup-b'),
      _song('dup-c'),
    ]);

    notifier.playNext(_song('dup-c'));

    expect(
      notifier.state.playlist.map((song) => song.id),
      ['dup-a', 'dup-c', 'dup-b'],
    );
    expect(notifier.state.currentIndex, 0);

    // 当前曲目与"已经是下一首"的曲目都是 no-op。
    notifier.playNext(_song('dup-a'));
    expect(
      notifier.state.playlist.map((song) => song.id),
      ['dup-a', 'dup-c', 'dup-b'],
    );
    notifier.playNext(_song('dup-c'));
    expect(
      notifier.state.playlist.map((song) => song.id),
      ['dup-a', 'dup-c', 'dup-b'],
    );
  });

  test('playNext keeps the current index when reordering from behind', () async {
    final notifier = PlayerNotifier(
      audioController: _FakeAudioController(),
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(notifier.dispose);

    await notifier.playPlaylist([
      _song('move-a'),
      _song('move-b'),
      _song('move-c'),
    ]);
    await notifier.skipToNext();
    expect(notifier.state.currentSong?.id, 'move-b');

    // 把当前位置之前的曲目搬到"下一首"：当前曲目必须仍然指向 move-b。
    notifier.playNext(_song('move-a'));

    expect(
      notifier.state.playlist.map((song) => song.id),
      ['move-b', 'move-a', 'move-c'],
    );
    expect(notifier.state.currentIndex, 0);
    expect(notifier.state.currentSong?.id, 'move-b');
  });

  test('playNext on an empty queue matches addToQueue semantics', () async {
    final audio = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(notifier.dispose);

    notifier.playNext(_song('empty-a'));

    expect(notifier.state.playlist.map((song) => song.id), ['empty-a']);
    expect(notifier.state.currentIndex, -1);
    expect(notifier.state.currentSong, isNull);
    // addToQueue 语义：只入队，不自动播放。
    expect(audio.playCalls, 0);

    notifier.playNext(_song('empty-a'));
    expect(notifier.state.playlist.map((song) => song.id), ['empty-a']);
  });

  test('a recreated controller receives the equalizer settings and volume', () async {
    final hangingAudio = _FakeAudioController(hangOnStop: true);
    final recreated = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: hangingAudio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioOperationTimeout: const Duration(milliseconds: 20),
      audioDisposeTimeout: const Duration(milliseconds: 20),
      audioControllerFactory: () => recreated,
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(notifier.dispose);

    await notifier.applyEqualizerSettings(
      const AudioEffectsSettings(
        equalizerEnabled: true,
        equalizerPreset: EqualizerPreset.rock,
      ),
    );
    expect(recreated.equalizerEnabledChanges, isEmpty);

    // stop() 挂起 → playSong 内部走 _recreatePlayer，新控制器是全新的
    // （EQ 关闭、音量回默认），必须把用户设置补推上去。
    await notifier.playSong(_song('recreate-settings'));

    expect(recreated.equalizerEnabledChanges, [true]);
    expect(recreated.equalizerBandGainChanges, [
      const EqualizerBandGain(0, 4),
      const EqualizerBandGain(1, 2),
      const EqualizerBandGain(2, 0),
      const EqualizerBandGain(3, 3),
      const EqualizerBandGain(4, 5),
    ]);
    expect(recreated.volumeChanges, contains(1.0));
  });

  test('a hanging seek does not block playing another song', () async {
    final hangingSeekAudio = _FakeAudioController(hangOnSeek: true);
    final notifier = PlayerNotifier(
      audioController: hangingSeekAudio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
    );
    addTearDown(notifier.dispose);

    unawaited(notifier.seek(const Duration(seconds: 30)));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await expectLater(
      notifier
          .playSong(_song('seek-recovery'))
          .timeout(const Duration(milliseconds: 200)),
      completes,
    );
    expect(notifier.state.currentSong?.id, 'seek-recovery');
  });

  test('a hanging quality switch does not block play controls', () async {
    final switchCompleter = Completer<String>();
    final controller = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: controller,
      audioControllerFactory: () => _FakeAudioController(),
      audioOperationTimeout: const Duration(milliseconds: 30),
      platformResolver: (_) => _QualityHangPlatform(
        normalUrl: 'https://example.test/song.mp3',
        qualityCompleter: switchCompleter,
      ),
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('quality-hang'));
    unawaited(notifier.switchQuality(AudioLevel.lossless));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await notifier.togglePlay().timeout(const Duration(milliseconds: 200));

    expect(notifier.state.isTransitioning, isFalse);
  });

  test(
    'a quality switch interrupted by playSong does not latch the quality gate',
    () async {
      // S-1 回归：换音质飞行中 playSong 推走质量纪元，旧代码的
      // `finally { if (requestId == _qualityRequestId) ... }` 于是永不复位，
      // `_isSwitchingQuality` 保持 true —— 之后所有换音质都在闸门处静默返回，
      // 并连带关闭健康监测（:457）与音量守护（:510）。
      final switchCompleter = Completer<String>();
      final audio = _FakeAudioController();
      final platform = _QualityHangPlatform(
        normalUrl: 'https://example.test/gate-a.mp3',
        qualityCompleter: switchCompleter,
      );
      final notifier = PlayerNotifier(
        audioController: audio,
        audioControllerFactory: () => _FakeAudioController(),
        platformResolver: (_) => platform,
        audioOperationTimeout: const Duration(seconds: 5),
        qualitySwitchTimeout: const Duration(seconds: 5),
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('gate-a'));

      final switchCall = notifier.switchQuality(AudioLevel.lossless);
      await pumpEventQueue();

      final nextSongCall = notifier.playSong(_song('gate-b'));
      await pumpEventQueue();

      switchCompleter.complete('https://example.test/gate-a-lossless.flac');
      await switchCall.timeout(const Duration(milliseconds: 500));
      await nextSongCall.timeout(const Duration(milliseconds: 500));
      await pumpEventQueue();

      await notifier
          .switchQuality(AudioLevel.medium)
          .timeout(const Duration(milliseconds: 500));

      expect(notifier.state.currentQuality, AudioLevel.medium);
    },
  );

  test('fadeOutAndPause ramps to silence before pausing', () async {
    final audio = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('sleep-fade'));
    audio.volumeChanges.clear();

    await notifier.fadeOutAndPause(
      duration: const Duration(milliseconds: 30),
    );

    expect(audio.pauseCalls, 1);
    expect(notifier.state.isPlaying, isFalse);
    expect(audio.volumeChanges, contains(0.0));
    // 淡出后必须把音量复位，否则下一次播放是静音的。
    expect(audio.volumeChanges.last, 1.0);
  });

  test('setPlaybackSpeed forwards the speed to a capable backend', () async {
    final audio = _FakeCapableAudioController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeCapableAudioController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(notifier.dispose);

    expect(notifier.supportsPlaybackSpeed, isTrue);

    await notifier.setPlaybackSpeed(1.5);
    expect(audio.speedChanges, [1.5]);
    expect(notifier.state.playbackSpeed, 1.5);

    // 越界值被夹到 0.5–2.0。
    await notifier.setPlaybackSpeed(9);
    expect(audio.speedChanges.last, 2.0);
    expect(notifier.state.playbackSpeed, 2.0);
  });

  test('setPlaybackSpeed degrades honestly on a plain backend', () async {
    final notifier = PlayerNotifier(
      audioController: _FakeAudioController(),
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(notifier.dispose);

    expect(notifier.supportsPlaybackSpeed, isFalse);
    expect(notifier.supportsSkipSilence, isFalse);

    await notifier.setPlaybackSpeed(1.5);
    expect(notifier.state.error, contains('不支持'));
    expect(notifier.state.playbackSpeed, 1.0);

    await notifier.setSkipSilence(true);
    expect(notifier.state.error, contains('不支持'));
    expect(notifier.state.skipSilence, isFalse);
  });

  test('setSkipSilence forwards the flag to a capable backend', () async {
    final audio = _FakeCapableAudioController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeCapableAudioController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(notifier.dispose);

    await notifier.setSkipSilence(true);

    expect(audio.skipSilenceChanges, [true]);
    expect(notifier.state.skipSilence, isTrue);
  });

  test('A-B loop seeks back to A once playback passes B', () async {
    final audio = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('ab-loop'));
    notifier.setAbLoopStart(const Duration(seconds: 10));
    notifier.setAbLoopEnd(const Duration(seconds: 20));
    expect(notifier.state.hasAbLoop, isTrue);

    audio.seekCalls = 0;
    audio.emitPosition(const Duration(seconds: 21));
    await pumpEventQueue();
    await pumpEventQueue();

    expect(audio.seekCalls, 1);
    expect(audio.position, const Duration(seconds: 10));
  });

  test('A-B loop ignores a B point that is not after A', () async {
    final notifier = PlayerNotifier(
      audioController: _FakeAudioController(),
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(notifier.dispose);

    notifier.setAbLoopStart(const Duration(seconds: 30));
    notifier.setAbLoopEnd(const Duration(seconds: 10));

    expect(notifier.state.hasAbLoop, isFalse);
    expect(notifier.state.error, contains('B 点'));
  });

  test('a new song clears the A-B loop', () async {
    final notifier = PlayerNotifier(
      audioController: _FakeAudioController(),
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('ab-first'));
    notifier.setAbLoopStart(const Duration(seconds: 5));
    notifier.setAbLoopEnd(const Duration(seconds: 15));
    expect(notifier.state.hasAbLoop, isTrue);

    await notifier.playSong(_song('ab-second'));

    expect(notifier.state.hasAbLoop, isFalse);
  });

  test('shuffle plays every song before repeating any', () async {
    // 旧实现每次 skipToNext 都新建 Random() 且只排除 currentIndex，
    // 长队列里反复播同一批歌（有放回抽样）。
    final notifier = PlayerNotifier(
      audioController: _FakeAudioController(),
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      random: _ScriptedRandom(const [1, 2]),
    );
    addTearDown(notifier.dispose);

    await notifier.playPlaylist([
      _song('shuffle-1'),
      _song('shuffle-2'),
      _song('shuffle-3'),
      _song('shuffle-4'),
    ]);
    notifier.toggleShuffle();

    final played = <String>{notifier.state.currentSong!.id};
    for (var i = 0; i < 3; i++) {
      await notifier.skipToNext();
      played.add(notifier.state.currentSong!.id);
    }

    expect(played.length, 4);
  });

  test('keeps a manually selected fixed quality for the next song', () async {
    final platform = _FakeMusicPlatform();
    final notifier = PlayerNotifier(
      audioController: _FakeAudioController(),
      platformResolver: (_) => platform,
      audioControllerFactory: () => _FakeAudioController(),
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('fixed-quality-1'));
    await notifier.switchQuality(AudioLevel.medium);
    await notifier.playSong(_song('fixed-quality-2'));

    expect(notifier.state.currentQuality, AudioLevel.medium);
    expect(
      platform.requestedQualitiesFor('fixed-quality-2'),
      contains(AudioLevel.medium),
    );
    expect(
      platform.requestedQualitiesFor('fixed-quality-2'),
      isNot(contains(AudioLevel.low)),
    );
  });

  test(
    'highest quality preference resolves each new song to its own highest quality',
    () async {
      final platform = _FakeMusicPlatform(
        qualitiesBySong: {
          'highest-1': const [
            AudioQuality(level: AudioLevel.low, bitrate: 128000, format: 'mp3'),
            AudioQuality(
              level: AudioLevel.lossless,
              bitrate: 999000,
              format: 'flac',
            ),
          ],
          'highest-2': const [
            AudioQuality(level: AudioLevel.low, bitrate: 128000, format: 'mp3'),
            AudioQuality(
              level: AudioLevel.master,
              bitrate: 3200000,
              format: 'flac',
            ),
          ],
        },
      );
      final notifier = PlayerNotifier(
        audioController: _FakeAudioController(),
        platformResolver: (_) => platform,
        audioControllerFactory: () => _FakeAudioController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('highest-1'));
      await notifier.switchQuality(AudioLevel.lossless, preferHighest: true);
      await notifier.playSong(_song('highest-2'));

      expect(notifier.state.currentQuality, AudioLevel.master);
      expect(notifier.state.qualityPreference, AudioQualityPreference.highest);
      expect(
        platform.requestedQualitiesFor('highest-2'),
        contains(AudioLevel.master),
      );
      expect(platform.availableQualityRequests, containsAll(['highest-2']));
    },
  );

  test('persists highest quality preference in playback memory', () async {
    final store = _MemoryPlaybackStore();
    final platform = _FakeMusicPlatform(
      qualitiesBySong: {
        'remember-highest': const [
          AudioQuality(level: AudioLevel.low, bitrate: 128000, format: 'mp3'),
          AudioQuality(
            level: AudioLevel.master,
            bitrate: 3200000,
            format: 'flac',
          ),
        ],
      },
    );
    final notifier = PlayerNotifier(
      audioController: _FakeAudioController(),
      audioControllerFactory: () => _FakeAudioController(),
      platformResolver: (_) => platform,
      playbackMemoryStore: store,
      playbackMemorySaveInterval: Duration.zero,
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('remember-highest'));
    await notifier.switchQuality(AudioLevel.master, preferHighest: true);

    expect(store.saved?.currentQuality, AudioLevel.master);
    expect(store.saved?.qualityPreference, AudioQualityPreference.highest);
  });

  test(
    'playSong plays local files without resolving a remote platform',
    () async {
      final audio = _FakeAudioController();
      final notifier = PlayerNotifier(
        audioController: audio,
        audioControllerFactory: () => _FakeAudioController(),
        platformResolver: (_) =>
            throw StateError('remote resolver should not be called'),
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(
        _song('D:\\Music\\local.mp3', platform: PlatformType.local),
      );

      expect(audio.lastUrl, Uri.file('D:\\Music\\local.mp3').toString());
      expect(notifier.state.currentSong?.platform, PlatformType.local);
    },
  );

  test('persists the current song and playback position', () async {
    final store = _MemoryPlaybackStore();
    final notifier = PlayerNotifier(
      audioController: _FakeAudioController(),
      audioControllerFactory: () => _FakeAudioController(),
      platformResolver: (_) => _FakeMusicPlatform(),
      playbackMemoryStore: store,
      playbackMemorySaveInterval: Duration.zero,
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('remember-me'));
    await notifier.switchQuality(AudioLevel.medium);
    await notifier.seek(const Duration(minutes: 1, seconds: 23));

    expect(store.saved?.currentSong.id, 'remember-me');
    expect(store.saved?.position, const Duration(minutes: 1, seconds: 23));
    expect(store.saved?.currentQuality, AudioLevel.medium);
    expect(store.saved?.qualityPreference, AudioQualityPreference.fixed);
  });

  test('restores the last song and position without autoplay', () async {
    final store = _MemoryPlaybackStore(
      restored: PlayerPlaybackMemory(
        currentSong: _song('restored'),
        playlist: [_song('restored')],
        currentIndex: 0,
        position: const Duration(minutes: 2, seconds: 4),
        duration: const Duration(minutes: 4),
        currentQuality: AudioLevel.medium,
      ),
    );
    final notifier = PlayerNotifier(
      audioControllerFactory: () => _FakeAudioController(),
      platformResolver: (_) => _FakeMusicPlatform(),
      playbackMemoryStore: store,
      playbackMemorySaveInterval: Duration.zero,
    );
    addTearDown(notifier.dispose);

    await pumpEventQueue();

    expect(notifier.state.currentSong?.id, 'restored');
    expect(notifier.state.position, const Duration(minutes: 2, seconds: 4));
    expect(notifier.state.duration, const Duration(minutes: 4));
    expect(notifier.state.currentQuality, AudioLevel.medium);
    expect(notifier.state.isPlaying, isFalse);
  });

  test(
    'offline mode plays the downloaded file without touching the network',
    () async {
      final audio = _FakeAudioController();
      final platform = _FakeMusicPlatform();
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => platform,
        audioControllerFactory: () => _FakeAudioController(),
        keepAliveController: const NoopPlaybackKeepAliveController(),
        isOfflineModeEnabled: () => true,
        offlineFilePathResolver: (song) async => r'C:\music\offline-1.mp3',
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('offline-1'));

      expect(platform.requestedQualitiesFor('offline-1'), isEmpty);
      expect(audio.lastUrl, startsWith('file:'));
      expect(audio.lastUrl, contains('offline-1.mp3'));
      expect(notifier.state.isPlaying, isTrue);
    },
  );

  test('offline mode off keeps streaming from the network', () async {
    final audio = _FakeAudioController();
    final platform = _FakeMusicPlatform();
    var resolveCalls = 0;
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => platform,
      audioControllerFactory: () => _FakeAudioController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
      // 开关关闭时即便本地有文件也不能抢走播放优先级。
      isOfflineModeEnabled: () => false,
      offlineFilePathResolver: (song) async {
        resolveCalls++;
        return r'C:\music\offline-2.mp3';
      },
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('offline-2'));

    expect(resolveCalls, 0);
    expect(platform.requestedQualitiesFor('offline-2'), [AudioLevel.low]);
    expect(audio.lastUrl, 'https://example.test/offline-2-low.mp3');
  });

  test('a missing local file falls back to the network', () async {
    final audio = _FakeAudioController();
    final platform = _FakeMusicPlatform();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => platform,
      audioControllerFactory: () => _FakeAudioController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
      isOfflineModeEnabled: () => true,
      offlineFilePathResolver: (song) async => null,
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('offline-3'));

    expect(platform.requestedQualitiesFor('offline-3'), [AudioLevel.low]);
    expect(audio.lastUrl, 'https://example.test/offline-3-low.mp3');
  });

  test('a failing local file lookup falls back to the network', () async {
    final audio = _FakeAudioController();
    final platform = _FakeMusicPlatform();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => platform,
      audioControllerFactory: () => _FakeAudioController(),
      keepAliveController: const NoopPlaybackKeepAliveController(),
      isOfflineModeEnabled: () => true,
      offlineFilePathResolver: (song) async =>
          throw StateError('local store unavailable'),
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('offline-4'));

    expect(platform.requestedQualitiesFor('offline-4'), [AudioLevel.low]);
    expect(audio.lastUrl, 'https://example.test/offline-4-low.mp3');
    expect(notifier.state.isPlaying, isTrue);
  });

  test(
    'restoring a song in offline mode also prefers the downloaded file',
    () async {
      final audio = _FakeAudioController();
      final platform = _FakeMusicPlatform();
      final store = _MemoryPlaybackStore(
        restored: PlayerPlaybackMemory(
          currentSong: _song('offline-restored'),
          playlist: [_song('offline-restored')],
          currentIndex: 0,
          position: const Duration(seconds: 30),
          duration: const Duration(minutes: 4),
          currentQuality: AudioLevel.medium,
        ),
      );
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => platform,
        audioControllerFactory: () => _FakeAudioController(),
        playbackMemoryStore: store,
        playbackMemorySaveInterval: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
        isOfflineModeEnabled: () => true,
        offlineFilePathResolver: (song) async =>
            r'C:\music\offline-restored.flac',
      );
      addTearDown(notifier.dispose);

      await pumpEventQueue();
      expect(notifier.state.currentSong?.id, 'offline-restored');

      await notifier.togglePlay();
      await pumpEventQueue();

      expect(platform.requestedQualitiesFor('offline-restored'), isEmpty);
      expect(audio.lastUrl, startsWith('file:'));
      expect(audio.lastUrl, contains('offline-restored.flac'));
    },
  );

  test(
    'play after restore loads the source and resumes from the saved position',
    () async {
      final audio = _FakeAudioController();
      final store = _MemoryPlaybackStore(
        restored: PlayerPlaybackMemory(
          currentSong: _song('resume-me'),
          playlist: [_song('resume-me')],
          currentIndex: 0,
          position: const Duration(seconds: 42),
          duration: const Duration(minutes: 3),
          currentQuality: AudioLevel.low,
        ),
      );
      final notifier = PlayerNotifier(
        audioController: audio,
        audioControllerFactory: () => _FakeAudioController(),
        platformResolver: (_) => _FakeMusicPlatform(),
        playbackMemoryStore: store,
        playbackMemorySaveInterval: Duration.zero,
      );
      addTearDown(notifier.dispose);

      await pumpEventQueue();
      await notifier.togglePlay();

      expect(audio.lastUrl, 'https://example.test/resume-me-low.mp3');
      expect(audio.seekCalls, 1);
      expect(audio.position, const Duration(seconds: 42));
      expect(audio.playCalls, 1);
      expect(notifier.state.isPlaying, isTrue);
    },
  );

  test(
    'Android health check recovers stalled online playback without changing song',
    () async {
      PlatformUtils.setDebugOverride(AppPlatform.android);
      addTearDown(() => PlatformUtils.setDebugOverride(null));
      final clock = _FakeClock();
      final audio = _FakeAudioController();
      final platform = _FakeMusicPlatform();
      final notifier = PlayerNotifier(
        audioController: audio,
        audioControllerFactory: () => _FakeAudioController(),
        platformResolver: (_) => platform,
        playbackHealthCheckInterval: Duration.zero,
        playbackStallThreshold: const Duration(milliseconds: 12),
        playbackRecoveryCooldown: const Duration(milliseconds: 30),
        playbackStartupGracePeriod: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
        now: clock.now,
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('online-stall'));
      audio.emitPosition(const Duration(seconds: 20));
      await pumpEventQueue();

      await notifier.runPlaybackHealthCheckForTest();
      expect(audio.setUrlCalls, 1);

      clock.advance(const Duration(milliseconds: 13));
      await notifier.runPlaybackHealthCheckForTest();
      await pumpEventQueue();

      expect(notifier.state.currentSong?.id, 'online-stall');
      expect(platform.requestedQualitiesFor('online-stall'), [
        AudioLevel.low,
        AudioLevel.low,
      ]);
      expect(audio.setUrlCalls, 2);
      expect(audio.seekCalls, 1);
      expect(audio.position, const Duration(seconds: 20));
      expect(audio.playCalls, 2);
      expect(audio.volumeChanges.last, 1);
    },
  );

  test(
    'stall recovery holds the audio mutex so playSong cannot interleave',
    () async {
      // S-6 回归：自愈做的是 stop/setUrl/seek/play 这一整套传输序列，以前被当作
      // "内部恢复"豁免 _AudioMutex 而裸奔执行，于是能和持锁的 playSong 交错，
      // 表现为「点了 B 却在放 A」。
      PlatformUtils.setDebugOverride(AppPlatform.android);
      addTearDown(() => PlatformUtils.setDebugOverride(null));
      final clock = _FakeClock();
      final audio = _FakeAudioController();
      final recoveryCompleter = Completer<String>();
      final platform = _RecoveryHangPlatform(
        recoveryCompleter: recoveryCompleter,
      );
      final notifier = PlayerNotifier(
        audioController: audio,
        audioControllerFactory: () => _FakeAudioController(),
        platformResolver: (_) => platform,
        playbackHealthCheckInterval: Duration.zero,
        playbackStallThreshold: const Duration(milliseconds: 10),
        playbackRecoveryCooldown: Duration.zero,
        playbackStartupGracePeriod: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
        now: clock.now,
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('stall-a'));
      audio.emitPosition(const Duration(seconds: 20));
      await pumpEventQueue();
      platform.requestedSongIds.clear();

      clock.advance(const Duration(milliseconds: 11));
      final healthCheck = notifier.runPlaybackHealthCheckForTest();
      await pumpEventQueue();
      await pumpEventQueue();

      // 自愈已进入 _mutex，卡在取 URL 上。
      expect(platform.requestedSongIds, ['stall-a']);

      final playCall = notifier.playSong(_song('stall-b'));
      await pumpEventQueue();
      await pumpEventQueue();

      // 自愈仍持锁 → playSong 不得抢在它之前调用平台。
      expect(platform.requestedSongIds, isNot(contains('stall-b')));

      recoveryCompleter.complete('https://example.test/stall-a-recovered.mp3');
      await healthCheck.timeout(const Duration(milliseconds: 500));
      await playCall.timeout(const Duration(milliseconds: 500));
      await pumpEventQueue();

      expect(notifier.state.currentSong?.id, 'stall-b');
      expect(audio.lastUrl, contains('stall-b'));
    },
  );

  test(
    'Android health check does not recover while position advances',
    () async {
      PlatformUtils.setDebugOverride(AppPlatform.android);
      addTearDown(() => PlatformUtils.setDebugOverride(null));
      final clock = _FakeClock();
      final audio = _FakeAudioController();
      final platform = _FakeMusicPlatform();
      final notifier = PlayerNotifier(
        audioController: audio,
        audioControllerFactory: () => _FakeAudioController(),
        platformResolver: (_) => platform,
        playbackHealthCheckInterval: Duration.zero,
        playbackStallThreshold: const Duration(milliseconds: 12),
        playbackRecoveryCooldown: const Duration(milliseconds: 30),
        playbackStartupGracePeriod: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
        now: clock.now,
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('advancing'));
      for (var i = 1; i <= 4; i++) {
        clock.advance(const Duration(milliseconds: 10));
        audio.emitPosition(Duration(seconds: i * 2));
        await pumpEventQueue();
        await notifier.runPlaybackHealthCheckForTest();
      }

      expect(platform.requestedQualitiesFor('advancing'), [AudioLevel.low]);
      expect(audio.setUrlCalls, 1);
    },
  );

  test(
    'Android health check ignores short buffering below stall threshold',
    () async {
      PlatformUtils.setDebugOverride(AppPlatform.android);
      addTearDown(() => PlatformUtils.setDebugOverride(null));
      final clock = _FakeClock();
      final audio = _FakeAudioController();
      final platform = _FakeMusicPlatform();
      final notifier = PlayerNotifier(
        audioController: audio,
        audioControllerFactory: () => _FakeAudioController(),
        platformResolver: (_) => platform,
        playbackHealthCheckInterval: Duration.zero,
        playbackStallThreshold: const Duration(milliseconds: 12),
        playbackRecoveryCooldown: const Duration(milliseconds: 30),
        playbackStartupGracePeriod: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
        now: clock.now,
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('short-buffer'));
      audio.emitPosition(const Duration(seconds: 20));
      audio.emitState(
        playing: true,
        processingState: just_audio.ProcessingState.buffering,
      );
      await pumpEventQueue();
      clock.advance(const Duration(milliseconds: 8));

      await notifier.runPlaybackHealthCheckForTest();

      expect(platform.requestedQualitiesFor('short-buffer'), [AudioLevel.low]);
      expect(audio.setUrlCalls, 1);
    },
  );

  test('Android health check ignores recent seek grace period', () async {
    PlatformUtils.setDebugOverride(AppPlatform.android);
    addTearDown(() => PlatformUtils.setDebugOverride(null));
    final clock = _FakeClock();
    final audio = _FakeAudioController();
    final platform = _FakeMusicPlatform();
    final notifier = PlayerNotifier(
      audioController: audio,
      audioControllerFactory: () => _FakeAudioController(),
      platformResolver: (_) => platform,
      playbackHealthCheckInterval: Duration.zero,
      playbackStallThreshold: const Duration(milliseconds: 12),
      playbackRecoveryCooldown: const Duration(milliseconds: 30),
      playbackStartupGracePeriod: const Duration(milliseconds: 50),
      keepAliveController: const NoopPlaybackKeepAliveController(),
      now: clock.now,
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('seek-grace'));
    await notifier.seek(const Duration(seconds: 30));
    audio.emitState(
      playing: true,
      processingState: just_audio.ProcessingState.buffering,
    );
    await pumpEventQueue();
    clock.advance(const Duration(milliseconds: 20));

    await notifier.runPlaybackHealthCheckForTest();

    expect(platform.requestedQualitiesFor('seek-grace'), [AudioLevel.low]);
    expect(audio.setUrlCalls, 1);
  });

  test('Android health check ignores songs near the end', () async {
    PlatformUtils.setDebugOverride(AppPlatform.android);
    addTearDown(() => PlatformUtils.setDebugOverride(null));
    final clock = _FakeClock();
    final audio = _FakeAudioController();
    final platform = _FakeMusicPlatform();
    final notifier = PlayerNotifier(
      audioController: audio,
      audioControllerFactory: () => _FakeAudioController(),
      platformResolver: (_) => platform,
      playbackHealthCheckInterval: Duration.zero,
      playbackStallThreshold: const Duration(milliseconds: 12),
      playbackRecoveryCooldown: const Duration(milliseconds: 30),
      playbackStartupGracePeriod: Duration.zero,
      keepAliveController: const NoopPlaybackKeepAliveController(),
      now: clock.now,
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('near-end'));
    audio.emitDuration(const Duration(minutes: 3));
    audio.emitPosition(const Duration(minutes: 2, seconds: 58));
    audio.emitState(
      playing: true,
      processingState: just_audio.ProcessingState.buffering,
    );
    await pumpEventQueue();
    clock.advance(const Duration(milliseconds: 20));

    await notifier.runPlaybackHealthCheckForTest();

    expect(platform.requestedQualitiesFor('near-end'), [AudioLevel.low]);
    expect(audio.setUrlCalls, 1);
  });

  test('Android health check ignores paused playback', () async {
    PlatformUtils.setDebugOverride(AppPlatform.android);
    addTearDown(() => PlatformUtils.setDebugOverride(null));
    final clock = _FakeClock();
    final audio = _FakeAudioController();
    final platform = _FakeMusicPlatform();
    final notifier = PlayerNotifier(
      audioController: audio,
      audioControllerFactory: () => _FakeAudioController(),
      platformResolver: (_) => platform,
      playbackHealthCheckInterval: Duration.zero,
      playbackStallThreshold: const Duration(milliseconds: 12),
      playbackRecoveryCooldown: const Duration(milliseconds: 30),
      playbackStartupGracePeriod: Duration.zero,
      keepAliveController: const NoopPlaybackKeepAliveController(),
      now: clock.now,
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('paused'));
    await notifier.pause();
    clock.advance(const Duration(milliseconds: 20));

    await notifier.runPlaybackHealthCheckForTest();

    expect(platform.requestedQualitiesFor('paused'), [AudioLevel.low]);
    expect(audio.setUrlCalls, 1);
  });

  test('Android health check does not recover local songs', () async {
    PlatformUtils.setDebugOverride(AppPlatform.android);
    addTearDown(() => PlatformUtils.setDebugOverride(null));
    final clock = _FakeClock();
    final audio = _FakeAudioController();
    final platform = _FakeMusicPlatform();
    final notifier = PlayerNotifier(
      audioController: audio,
      audioControllerFactory: () => _FakeAudioController(),
      platformResolver: (_) => platform,
      playbackHealthCheckInterval: Duration.zero,
      playbackStallThreshold: const Duration(milliseconds: 12),
      playbackRecoveryCooldown: const Duration(milliseconds: 30),
      playbackStartupGracePeriod: Duration.zero,
      keepAliveController: const NoopPlaybackKeepAliveController(),
      now: clock.now,
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(
      _song('content://local/song.mp3', platform: PlatformType.local),
    );
    audio.emitPosition(const Duration(seconds: 20));
    await pumpEventQueue();
    clock.advance(const Duration(milliseconds: 20));

    await notifier.runPlaybackHealthCheckForTest();

    expect(platform.requestedQualities, isEmpty);
    expect(audio.setUrlCalls, 1);
  });

  test('Android health check respects recovery cooldown', () async {
    PlatformUtils.setDebugOverride(AppPlatform.android);
    addTearDown(() => PlatformUtils.setDebugOverride(null));
    final clock = _FakeClock();
    final audio = _FakeAudioController();
    final platform = _FakeMusicPlatform();
    final notifier = PlayerNotifier(
      audioController: audio,
      audioControllerFactory: () => _FakeAudioController(),
      platformResolver: (_) => platform,
      playbackHealthCheckInterval: Duration.zero,
      playbackStallThreshold: const Duration(milliseconds: 10),
      playbackRecoveryCooldown: const Duration(milliseconds: 60),
      playbackStartupGracePeriod: Duration.zero,
      keepAliveController: const NoopPlaybackKeepAliveController(),
      now: clock.now,
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('cooldown'));
    audio.emitPosition(const Duration(seconds: 20));
    await pumpEventQueue();
    clock.advance(const Duration(milliseconds: 11));
    await notifier.runPlaybackHealthCheckForTest();
    clock.advance(const Duration(milliseconds: 30));
    await notifier.runPlaybackHealthCheckForTest();

    expect(platform.requestedQualitiesFor('cooldown'), [
      AudioLevel.low,
      AudioLevel.low,
    ]);
    expect(audio.setUrlCalls, 2);
  });

  test(
    'Android health check stops automatic recovery after two attempts',
    () async {
      PlatformUtils.setDebugOverride(AppPlatform.android);
      addTearDown(() => PlatformUtils.setDebugOverride(null));
      final clock = _FakeClock();
      final audio = _FakeAudioController();
      final platform = _FakeMusicPlatform();
      final notifier = PlayerNotifier(
        audioController: audio,
        audioControllerFactory: () => _FakeAudioController(),
        platformResolver: (_) => platform,
        playbackHealthCheckInterval: Duration.zero,
        playbackStallThreshold: const Duration(milliseconds: 10),
        playbackRecoveryCooldown: Duration.zero,
        playbackStartupGracePeriod: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
        now: clock.now,
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('max-recovery'));
      audio.emitPosition(const Duration(seconds: 20));
      await pumpEventQueue();

      for (var i = 0; i < 3; i++) {
        clock.advance(const Duration(milliseconds: 11));
        await notifier.runPlaybackHealthCheckForTest();
      }

      expect(platform.requestedQualitiesFor('max-recovery'), [
        AudioLevel.low,
        AudioLevel.low,
        AudioLevel.low,
      ]);
      expect(audio.setUrlCalls, 3);
      expect(notifier.state.error, contains('Playback stalled repeatedly'));
    },
  );
group('diagnostics instrumentation', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mconnect_player_diag_');
      await DiagnosticsService.instance.initializeForTest(tempDir);
    });

    tearDown(() async {
      await DiagnosticsService.instance.resetForTest();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('volume writes are recorded to diagnostics', () async {
      final audio = _FakeAudioController();
      final notifier = PlayerNotifier(
        audioController: audio,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      notifier.setFadeOptions(
        enabled: false,
        duration: const Duration(milliseconds: 300),
      );
      await pumpEventQueue();

      expect(
        DiagnosticsService.instance.recentEvents.any(
          (e) => e.type == 'player' && e.message.contains('volume_set'),
        ),
        isTrue,
      );
    });

    test('failed volume writes are recorded as errors', () async {
      final audio = _FakeAudioController()..failOnSetVolume = true;
      final notifier = PlayerNotifier(
        audioController: audio,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      notifier.setFadeOptions(
        enabled: false,
        duration: const Duration(milliseconds: 300),
      );
      await pumpEventQueue();

      expect(
        DiagnosticsService.instance.recentEvents.any(
          (e) =>
              e.type == 'error' &&
              e.message.contains('setVolume'),
        ),
        isTrue,
      );
    });

    test('player state changes are recorded once per transition', () async {
      final audio = _FakeAudioController();
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => _FakeMusicPlatform(),
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('state-log'));
      audio.emitState(
        playing: true,
        processingState: just_audio.ProcessingState.ready,
      );
      await pumpEventQueue();
      // 相同状态重复上报不应产生第二条记录
      audio.emitState(
        playing: true,
        processingState: just_audio.ProcessingState.ready,
      );
      await pumpEventQueue();
      audio.emitState(
        playing: false,
        processingState: just_audio.ProcessingState.ready,
      );
      await pumpEventQueue();

      final states = DiagnosticsService.instance.recentEvents
          .where((e) => e.type == 'player' && e.message.contains('player_state'))
          .toList();
      expect(
        states.any((e) => e.message.contains('"playing":true')),
        isTrue,
      );
      expect(
        states.any((e) => e.message.contains('"playing":false')),
        isTrue,
      );
    });

    test('Android health check restores stale sub-unit volume', () async {
      PlatformUtils.setDebugOverride(AppPlatform.android);
      addTearDown(() => PlatformUtils.setDebugOverride(null));
      final audio = _FakeAudioController();
      final platform = _FakeMusicPlatform();
      final notifier = PlayerNotifier(
        audioController: audio,
        audioControllerFactory: () => _FakeAudioController(),
        platformResolver: (_) => platform,
        playbackHealthCheckInterval: Duration.zero,
        playbackStartupGracePeriod: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('volume-ok'));
      audio.emitPosition(const Duration(seconds: 20));
      await pumpEventQueue();
      // 模拟音量被外部路径压到 0.3（绕过 notifier 直接写播放器）。
      await audio.setVolume(0.3);
      await pumpEventQueue();

      await notifier.runPlaybackHealthCheckForTest();

      expect(audio.volume, 1.0);
      expect(audio.volumeChanges.contains(1.0), isTrue);
      expect(
        DiagnosticsService.instance.recentEvents.any(
          (e) =>
              e.type == 'player' &&
              e.message.contains('volume_watchdog_restore'),
        ),
        isTrue,
      );
    });

    test('Android health check leaves healthy volume untouched', () async {
      PlatformUtils.setDebugOverride(AppPlatform.android);
      addTearDown(() => PlatformUtils.setDebugOverride(null));
      final audio = _FakeAudioController();
      final platform = _FakeMusicPlatform();
      final notifier = PlayerNotifier(
        audioController: audio,
        audioControllerFactory: () => _FakeAudioController(),
        platformResolver: (_) => platform,
        playbackHealthCheckInterval: Duration.zero,
        playbackStartupGracePeriod: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('volume-healthy'));
      audio.emitPosition(const Duration(seconds: 20));
      await pumpEventQueue();

      await notifier.runPlaybackHealthCheckForTest();

      // 默认音量已是 1.0，不应产生新的 setVolume 调用。
      expect(audio.volumeChanges, isEmpty);
      expect(audio.volume, 1.0);
    });

    // --- 卡死修复 W1 -----------------------------------------------------

    test(
      'a wedged audio mutex does not block later taps and is bounded',
      () async {
        final wedging = _WedgingAudioController();
        final notifier = PlayerNotifier(
          audioController: wedging,
          platformResolver: (_) => _FakeMusicPlatform(),
          audioControllerFactory: () => _FakeAudioController(),
          // 让第一个 playSong 真的吊在锁内（而不是靠自身超时脱身）。
          audioOperationTimeout: const Duration(seconds: 30),
          audioDisposeTimeout: const Duration(milliseconds: 20),
          mutexWaitTimeout: const Duration(milliseconds: 40),
          mutexMaxPending: 3,
          stuckWatchdogInterval: Duration.zero,
          keepAliveController: const NoopPlaybackKeepAliveController(),
        );
        addTearDown(notifier.dispose);
        addTearDown(() {
          if (!wedging.stopGate.isCompleted) wedging.stopGate.complete();
        });

        // 第 1 次：卡在 _safeStop 上，永久持锁。
        unawaited(notifier.playSong(_song('wedge-hold')));
        await pumpEventQueue();

        // 连发 30 次：每一次都必须在超时/上界内返回，而不是永久排队。
        final followUps = [
          for (var i = 0; i < 30; i++) notifier.playSong(_song('wedge-$i')),
        ];
        await expectLater(
          Future.wait(followUps).timeout(const Duration(seconds: 10)),
          completes,
        );

        expect(
          DiagnosticsService.instance.recentEvents.any(
            (e) => e.type == 'player' && e.message.contains('audio_mutex_wedged'),
          ),
          isTrue,
          reason: '等待持锁者超时必须记 audio_mutex_wedged',
        );
        expect(
          DiagnosticsService.instance.recentEvents.any(
            (e) =>
                e.type == 'slow_operation' &&
                e.message.contains('audio_mutex_overflow'),
          ),
          isTrue,
          reason: '超过等待上界必须记 audio_mutex_overflow',
        );
      },
    );

    test('concurrent recreate triggers install exactly one new controller', () async {
      final failing = _SlowDisposeAudioController(
        hangOnStop: true,
        hangOnSeek: true,
        delay: const Duration(milliseconds: 150),
      );
      var created = 0;
      final notifier = PlayerNotifier(
        audioController: failing,
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () {
          created++;
          return _FakeAudioController();
        },
        audioOperationTimeout: const Duration(milliseconds: 20),
        audioDisposeTimeout: const Duration(seconds: 2),
        stuckWatchdogInterval: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      // 触发点 1：seek 超时 → _safeSeek 的 catch。
      unawaited(notifier.seek(const Duration(seconds: 30)));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // 触发点 2：stop 超时 → _safeStop 的 catch（此时第一次重建仍在 dispose 中）。
      unawaited(notifier.playSong(_song('recreate-once')));
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(created, 1, reason: '单飞守卫：并发触发只允许装一个新 controller');
      expect(
        failing.disposeCalls,
        1,
        reason: '并发重建不许对同一个 controller 各 dispose 一次（会 cancel 掉彼此在用的订阅）',
      );
      expect(notifier.hasAudioControllerForTest, isTrue);
    });

    test(
      'the stuck watchdog force-resets a transport wedged while "paused"',
      () async {
        final wedging = _WedgingAudioController();
        var created = 0;
        final notifier = PlayerNotifier(
          audioController: wedging,
          platformResolver: (_) => _FakeMusicPlatform(),
          audioControllerFactory: () {
            created++;
            return _FakeAudioController();
          },
          audioOperationTimeout: const Duration(seconds: 30),
          audioDisposeTimeout: const Duration(milliseconds: 20),
          mutexWaitTimeout: const Duration(milliseconds: 40),
          stuckWatchdogInterval: const Duration(milliseconds: 20),
          stuckWatchdogThreshold: const Duration(milliseconds: 60),
          keepAliveController: const NoopPlaybackKeepAliveController(),
        );
        addTearDown(notifier.dispose);
        addTearDown(() {
          if (!wedging.stopGate.isCompleted) wedging.stopGate.complete();
        });

        unawaited(notifier.playSong(_song('stuck-watchdog')));
        await pumpEventQueue();

        // 关键：这正是真机日志里的状态 —— 已经"不在播放"，所以 12s 停滞自愈
        // （要求 isPlaying && controller.playing）100% 不会触发。
        expect(notifier.state.isPlaying, isFalse);
        expect(notifier.state.isTransitioning, isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(
          notifier.state.isTransitioning,
          isFalse,
          reason: '看门狗必须复位过渡标志',
        );
        expect(notifier.isTransportBusyForTest, isFalse);
        expect(notifier.state.error, contains('已重置播放器'));
        expect(created, greaterThanOrEqualTo(1));
        expect(
          DiagnosticsService.instance.recentEvents.any(
            (e) => e.type == 'player' && e.message.contains('player_forced_reset'),
          ),
          isTrue,
        );
      },
    );

    test('a failed restore does not latch the restore flag', () async {
      final platform = _ErroringUrlPlatform(failingIds: const {'restore-fail'});
      final store = _MemoryPlaybackStore(
        restored: PlayerPlaybackMemory(
          currentSong: _song('restore-fail'),
          playlist: [_song('restore-fail')],
          currentIndex: 0,
          position: const Duration(seconds: 5),
          duration: const Duration(minutes: 3),
          currentQuality: AudioLevel.low,
        ),
      );
      final notifier = PlayerNotifier(
        audioController: _FakeAudioController(),
        platformResolver: (_) => platform,
        audioControllerFactory: () => _FakeAudioController(),
        playbackMemoryStore: store,
        playbackMemorySaveInterval: Duration.zero,
        stuckWatchdogInterval: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      await pumpEventQueue();
      expect(notifier.state.currentSong?.id, 'restore-fail');

      // 第一次：走恢复路径并失败。
      await notifier.togglePlay();
      await pumpEventQueue();
      expect(platform.requestedQualitiesFor('restore-fail'), hasLength(1));

      // 第二次：标志已复位 → 走普通 togglePlay，不再重试恢复取流。
      await notifier.togglePlay();
      await pumpEventQueue();

      expect(
        platform.requestedQualitiesFor('restore-fail'),
        hasLength(1),
        reason: '恢复失败必须清 _restoredSourceNeedsLoad，否则每次点击都重进失败路径',
      );
    });

    test(
      'a restored-but-idle player is NOT treated as a stuck transport',
      () async {
        // 真机日志（log日志/10-8.txt）里的死法：
        //   启动恢复播放记忆 → _restoredSourceNeedsLoad = true（用户还没点播放）
        //   → 卡死看门狗把"等我点播放"当成"卡死"
        //   → 30s 后 player_forced_reset {"reason":"transport_stuck",
        //      "restored_source_needs_load":true,"is_playing":false}
        //   → _playRequestId++ 作废在途请求 + _recreatePlayer()
        //   ⇒ 用户此刻点播放没有任何反应（"音乐无法播放"）。
        //
        // 本用例把这条链钉住：恢复记忆后**什么都不做**，看门狗不得复位。
        final store = _MemoryPlaybackStore(
          restored: PlayerPlaybackMemory(
            currentSong: _song('restored-idle'),
            playlist: [_song('restored-idle')],
            currentIndex: 0,
            position: const Duration(seconds: 9),
            duration: const Duration(minutes: 3),
            currentQuality: AudioLevel.low,
          ),
        );
        final notifier = PlayerNotifier(
          audioController: _FakeAudioController(),
          platformResolver: (_) => _ErroringUrlPlatform(failingIds: const {}),
          audioControllerFactory: () => _FakeAudioController(),
          playbackMemoryStore: store,
          playbackMemorySaveInterval: Duration.zero,
          // 阈值远长于本用例的观察窗（400ms），确保不靠"没到点"蒙过去。
          stuckWatchdogInterval: const Duration(milliseconds: 20),
          stuckWatchdogThreshold: const Duration(milliseconds: 60),
          keepAliveController: const NoopPlaybackKeepAliveController(),
        );
        addTearDown(notifier.dispose);

        await pumpEventQueue();
        expect(notifier.state.currentSong?.id, 'restored-idle');
        expect(notifier.isTransportBusyForTest, isTrue, reason: '恢复态已置位');

        // 用户没点任何东西，静置超过阈值。
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await pumpEventQueue();

        expect(
          DiagnosticsService.instance.recentEvents.any(
            (e) => e.type == 'player' && e.message.contains('player_forced_reset'),
          ),
          isFalse,
          reason: '恢复后等用户点播放 = 空闲，不是卡死；复位会作废在途请求并让播放无反应',
        );
        expect(
          notifier.isTransportBusyForTest,
          isTrue,
          reason: '不得被看门狗清掉恢复标志 —— 那会让首次点击走错分支',
        );

        // 真正的"点播放"仍然必须走恢复路径并成功出声。
        await notifier.togglePlay();
        await pumpEventQueue();
        expect(notifier.state.isPlaying, isTrue);
        expect(notifier.isTransportBusyForTest, isFalse);
      },
    );

    test('the playback failure chain writes every attempt to diagnostics', () async {      final notifier = PlayerNotifier(
        audioController: _FakeAudioController(),
        platformResolver: (_) =>
            _ErroringUrlPlatform(failingIds: const {'chain-1', 'chain-2'}),
        audioControllerFactory: () => _FakeAudioController(),
        stuckWatchdogInterval: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playPlaylist([_song('chain-1'), _song('chain-2')]);
      await pumpEventQueue();

      final messages = DiagnosticsService.instance.recentEvents
          .map((event) => event.message)
          .toList();
      expect(
        messages.any((m) => m.contains('playback_failure_chain_start')),
        isTrue,
      );
      expect(
        messages.any((m) => m.contains('playback_failure_skip_next')),
        isTrue,
        reason: '每次尝试都要有据可查，否则真机上的失败链无法复盘',
      );
    });
  });

  // Wave 0-A (item 2)：playSong 失败分支以前只是 `_setState(error: ...)` ——
  // 队列里明明还有下一首，用户却只能停在一首永远放不出来的歌上。
  group('Wave 0-A playback failure chain', () {
    test('a failed playSong falls back to the next track', () async {
      final platform = _ErroringUrlPlatform(
        failingIds: const {'fail-1', 'fail-2'},
      );
      final notifier = PlayerNotifier(
        audioController: _FakeAudioController(),
        platformResolver: (_) => platform,
        audioControllerFactory: () => _FakeAudioController(),
        stuckWatchdogInterval: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playPlaylist([_song('fail-1'), _song('fail-2')]);
      await pumpEventQueue();

      expect(
        notifier.state.currentSong?.id,
        'fail-2',
        reason: '取流全失败必须 skipToNext，而不是停在一首放不出来的歌上',
      );
      expect(notifier.state.error, isNotNull);
    });

    test('a failed playSong retries one quality step down first', () async {
      final audio = _FakeAudioController();
      final platform = _FailingHighQualityPlatform();
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => platform,
        audioControllerFactory: () => _FakeAudioController(),
        stuckWatchdogInterval: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playPlaylist([_song('quality-fallback')]);
      await notifier.switchQuality(AudioLevel.high);
      expect(notifier.state.currentQuality, AudioLevel.high);

      await notifier.playSong(_song('quality-fallback'));
      await pumpEventQueue();

      expect(notifier.state.error, isNull, reason: '降档成功必须把错误清掉');
      expect(notifier.state.currentQuality, AudioLevel.medium);
      expect(notifier.state.currentSong?.id, 'quality-fallback');
      expect(audio.lastUrl, contains('medium'));
    });

    test('the last failing track of the queue is reported, not skipped', () async {
      final notifier = PlayerNotifier(
        audioController: _FakeAudioController(),
        platformResolver: (_) =>
            _ErroringUrlPlatform(failingIds: const {'only-1'}),
        audioControllerFactory: () => _FakeAudioController(),
        stuckWatchdogInterval: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playPlaylist([_song('only-1')]);
      await pumpEventQueue();

      expect(notifier.state.currentSong?.id, 'only-1');
      expect(notifier.state.error, isNotNull);
      expect(notifier.state.isPlaying, isFalse);
    });
  });

  // Wave 0-A (A-2)：播放偏好必须跟着"上次播放"一起持久化。
  group('Wave 0-A playback preference persistence', () {
    test('restores playback preferences from the saved memory', () async {
      final store = _MemoryPlaybackStore(
        restored: PlayerPlaybackMemory.fromJson({
          'currentSong': _memorySongJson('pref-1'),
          'playlist': [_memorySongJson('pref-1')],
          'currentIndex': 0,
          'playbackSpeed': 1.5,
          'skipSilence': true,
          'isShuffle': true,
          'repeatMode': 'all',
          'abLoopStartMs': 12000,
          'abLoopEndMs': 34000,
        }),
      );
      final notifier = PlayerNotifier(
        playbackMemoryStore: store,
        audioController: _FakeAudioController(),
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () => _FakeAudioController(),
        stuckWatchdogInterval: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      await pumpEventQueue();

      expect(notifier.state.currentSong?.id, 'pref-1');
      expect(notifier.state.playbackSpeed, 1.5);
      expect(notifier.state.skipSilence, isTrue);
      expect(notifier.state.isShuffle, isTrue);
      expect(notifier.state.repeatMode, RepeatMode.all);
      expect(notifier.state.abLoopStart, const Duration(milliseconds: 12000));
      expect(notifier.state.abLoopEnd, const Duration(milliseconds: 34000));
    });

    test('persists playback preference changes', () async {
      final store = _MemoryPlaybackStore();
      final audio = _FakeCapableAudioController();
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () => _FakeCapableAudioController(),
        playbackMemoryStore: store,
        playbackMemorySaveInterval: Duration.zero,
        stuckWatchdogInterval: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('pref-2'));
      await notifier.setPlaybackSpeed(1.5);
      await notifier.setSkipSilence(true);
      notifier.toggleShuffle();
      notifier.cycleRepeatMode();
      notifier.setAbLoopStart(const Duration(seconds: 12));
      notifier.setAbLoopEnd(const Duration(seconds: 34));
      await notifier.flushPlaybackMemory();

      final saved = store.saved?.toJson();
      expect(saved, isNotNull);
      final json = saved!;
      expect(json['playbackSpeed'], 1.5);
      expect(json['skipSilence'], true);
      expect(json['isShuffle'], true);
      expect(json['repeatMode'], 'all');
      expect(json['abLoopStartMs'], 12000);
      expect(json['abLoopEndMs'], 34000);
      expect(json['currentSong']['id'], 'pref-2');
    });
  });

  // Wave 0-A (item 2)：跨平台换源是**可注入接缝**，本波默认 null。这条用例把
  // "接缝一旦接上，换源成功就不跳曲"固定下来，W1 接真实实现时不必重写失败链。
  group('Wave 0-A cross-source seam', () {
    test('an injected resolver plays the alternative source', () async {
      final audio = _FakeAudioController();
      final platform = _ErroringUrlPlatform(
        failingIds: const {'cross-1', 'cross-2'},
      );
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => platform,
        audioControllerFactory: () => _FakeAudioController(),
        // Wave 1-A：接缝返回 CrossSourceResult（URL + 来源平台），角标要用后者。
        crossSourceResolver: (song, quality) async => song.id == 'cross-1'
            ? const CrossSourceResult(
                url: 'https://example.test/cross-1-alt.mp3',
                platform: PlatformType.qq,
              )
            : null,
        stuckWatchdogInterval: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playPlaylist([_song('cross-1'), _song('cross-2')]);
      await pumpEventQueue();

      expect(audio.lastUrl, 'https://example.test/cross-1-alt.mp3');
      expect(
        notifier.state.sourcePlatform,
        PlatformType.qq,
        reason: '换源成功必须把来源平台写进 state，播放页角标才有数据',
      );
      expect(
        notifier.state.currentSong?.id,
        'cross-1',
        reason: '换源成功就不该再跳曲',
      );
      expect(notifier.state.error, isNull);
      expect(notifier.state.isPlaying, isTrue);
    });

    test('换源流半途断 → 当次失效该缓存；且每链只调一次 resolver（F3）', () async {
      final audio = _FakeAudioController()..failPlayWithAsyncError = true;
      final invalidated = <PlatformType>[];
      var resolverCalls = 0;
      final notifier = PlayerNotifier(
        audioController: audio,
        // 原平台对该曲取流全失败 → 必然走换源
        platformResolver: (_) => _ErroringUrlPlatform(failingIds: const {'f3-1'}),
        audioControllerFactory: () =>
            _FakeAudioController()..failPlayWithAsyncError = true,
        // 恢复到 high：使失败链的 attemptedQuality 是 high。旧实现会按
        // [high, medium, low] 逐档调用 resolver（3 次），新实现只调 1 次 ⇒ 有判别力。
        playbackMemoryStore: _MemoryPlaybackStore(
          restored: PlayerPlaybackMemory.fromJson({
            'currentSong': _memorySongJson('f3-1'),
            'playlist': [_memorySongJson('f3-1')],
            'currentIndex': 0,
            'currentQuality': 'high',
          }),
        ),
        crossSourceResolver: (song, quality) async {
          resolverCalls++;
          return const CrossSourceResult(
            url: 'https://cross.test/f3.mp3',
            platform: PlatformType.qq,
          );
        },
        invalidateCrossSource: (song, platform) async =>
            invalidated.add(platform),
        stuckWatchdogInterval: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      await pumpEventQueue(); // 等 A-2 恢复落地（currentQuality → high）
      await notifier.playSong(_song('f3-1'));
      await pumpEventQueue();

      expect(
        notifier.state.currentQuality,
        AudioLevel.high,
        reason: '前置条件：失败链的 attemptedQuality 必须是 high，否则 (b) 无判别力',
      );
      expect(
        resolverCalls,
        1,
        reason: '(b)：服务内部已逐级降档，失败链不得再按音质档循环调用',
      );
      expect(
        invalidated,
        [PlatformType.qq],
        reason: '换源来的直链放不出来 → 必须当次失效该平台缓存（F3）',
      );
    });
  });

  // Wave 0-A (P-1)：位置每秒 tick 一次，以前每次都重扫 likesProvider.songs
  // （最多 500 首）。现在只在喜欢列表变化时重建 Set。
  group('Wave 0-A per-tick liked lookup', () {
    test('position ticks do not re-resolve the liked songs', () async {
      final audio = _FakeAudioController();
      final notifications = _FakePlaybackNotificationController();
      var resolverCalls = 0;
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () => _FakeAudioController(),
        notificationController: notifications,
        isSongLiked: (_) {
          resolverCalls++;
          return true;
        },
        stuckWatchdogInterval: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playPlaylist([_song('liked-1')]);
      notifier.updateLikedSongs([_song('liked-1')]);
      expect(
        notifications.updates.last.isCurrentSongLiked,
        isTrue,
        reason: 'key 集合必须真的被通知层读到（见 likedSongKeyFor 的拼法）',
      );

      final resolverCallsAfterSeed = resolverCalls;
      for (var second = 1; second <= 10; second++) {
        audio.emitPosition(Duration(seconds: second));
        await pumpEventQueue();
      }
      expect(
        resolverCalls,
        resolverCallsAfterSeed,
        reason: 'P-1：位置 tick 不得再走 likesProvider.songs.any(...)（最多 500 首）',
      );

      notifier.updateLikedSongs(const <Song>[]);
      expect(
        notifications.updates.last.isCurrentSongLiked,
        isFalse,
        reason: '取消喜欢（列表变化）必须立刻反映到通知层',
      );
    });
  });

  // Wave 0-A (item 7)：W1-D 的队列页要用的编辑 API。
  group('Wave 0-A queue editing', () {
    ({PlayerNotifier notifier, _FakeAudioController audio}) buildQueue({
      PlayerPlaybackMemoryStore? store,
    }) {
      final audio = _FakeAudioController();
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () => _FakeAudioController(),
        playbackMemoryStore: store ?? const NoopPlayerPlaybackMemoryStore(),
        stuckWatchdogInterval: Duration.zero,
        keepAliveController: const NoopPlaybackKeepAliveController(),
      );
      addTearDown(notifier.dispose);
      return (notifier: notifier, audio: audio);
    }

    test('removeFromQueue drops the song and keeps the current one', () async {
      final queue = buildQueue();
      await queue.notifier.playPlaylist([
        _song('q-1'),
        _song('q-2'),
        _song('q-3'),
      ]);

      await queue.notifier.removeFromQueue(_song('q-3').dedupeKey);

      expect(queue.notifier.state.playlist.map((s) => s.id), ['q-1', 'q-2']);
      expect(queue.notifier.state.currentSong?.id, 'q-1');
      expect(queue.notifier.state.currentIndex, 0);
    });

    test('removeFromQueue hands playback over when the current song goes', () async {
      final queue = buildQueue();
      await queue.notifier.playPlaylist([
        _song('r-1'),
        _song('r-2'),
        _song('r-3'),
      ]);

      await queue.notifier.removeFromQueue(_song('r-1').dedupeKey);
      await pumpEventQueue();

      expect(queue.notifier.state.playlist.map((s) => s.id), ['r-2', 'r-3']);
      expect(queue.notifier.state.currentSong?.id, 'r-2');
      expect(queue.notifier.state.currentIndex, 0);
    });

    test('removeFromQueue of the last song clears the queue', () async {
      final queue = buildQueue();
      await queue.notifier.playPlaylist([_song('s-1')]);

      await queue.notifier.removeFromQueue(_song('s-1').dedupeKey);
      await pumpEventQueue();

      expect(queue.notifier.state.playlist, isEmpty);
      expect(queue.notifier.state.currentSong, isNull);
      expect(queue.notifier.state.isPlaying, isFalse);
    });

    test('clearQueue stops playback and empties the queue', () async {
      final store = _MemoryPlaybackStore();
      final queue = buildQueue(store: store);
      await queue.notifier.playPlaylist([_song('c-1'), _song('c-2')]);
      expect(queue.audio.playing, isTrue);

      await queue.notifier.clearQueue();

      expect(queue.notifier.state.playlist, isEmpty);
      expect(queue.notifier.state.currentSong, isNull);
      expect(queue.notifier.state.currentIndex, -1);
      expect(queue.notifier.state.isPlaying, isFalse);
      expect(queue.audio.playing, isFalse, reason: '清空队列必须真的停掉播放器');
      expect(
        store.cleared,
        isTrue,
        reason: '清空队列后重启不该把刚清掉的歌恢复回来',
      );
    });

    test('moveInQueue reorders without interrupting playback', () async {
      final queue = buildQueue();
      await queue.notifier.playPlaylist([
        _song('m-1'),
        _song('m-2'),
        _song('m-3'),
      ]);
      final setUrlCallsBefore = queue.audio.setUrlCalls;

      queue.notifier.moveInQueue(2, 0);

      expect(queue.notifier.state.playlist.map((s) => s.id), [
        'm-3',
        'm-1',
        'm-2',
      ]);
      expect(queue.notifier.state.currentSong?.id, 'm-1');
      expect(queue.notifier.state.currentIndex, 1);
      expect(
        queue.audio.setUrlCalls,
        setUrlCallsBefore,
        reason: '重排队列不得打断正在播的那一首',
      );
    });

    test('playAtIndex plays the entry and ignores out-of-range', () async {
      final queue = buildQueue();
      await queue.notifier.playPlaylist([_song('p-1'), _song('p-2')]);

      await queue.notifier.playAtIndex(1);
      expect(queue.notifier.state.currentSong?.id, 'p-2');
      expect(queue.notifier.state.currentIndex, 1);

      await queue.notifier.playAtIndex(9);
      expect(
        queue.notifier.state.currentSong?.id,
        'p-2',
        reason: '越界必须是 no-op',
      );
    });
  });
}

Song _song(
  String id, {
  PlatformType platform = PlatformType.netease,
  Duration duration = Duration.zero,
}) => Song(
  id: id,
  platform: platform,
  name: 'song $id',
  duration: duration,
  artists: const [Artist(id: 'artist', name: 'artist')],
);

/// 与 [_song] 等价的一份 JSON，用来构造 `PlayerPlaybackMemory`（A-2 用例）。
Map<String, dynamic> _memorySongJson(String id) => {
  'id': id,
  'platform': 'netease',
  'name': 'song $id',
  'artists': [
    {'id': 'artist', 'name': 'artist'},
  ],
  'durationMs': 180000,
};

class _FakeClock {
  DateTime _now = DateTime(2026);

  DateTime now() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }
}

/// Deterministic [Random] that cycles a fixed script, so shuffle tests do not
/// depend on dart:math's implementation staying stable.
class _ScriptedRandom implements Random {
  final List<int> _values;
  int _cursor = 0;

  _ScriptedRandom(this._values);

  @override
  int nextInt(int max) {
    final value = _values[_cursor++ % _values.length];
    return max <= 1 ? 0 : value % max;
  }

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

class _FakeAudioController implements PlayerAudioController {
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _playerStateController =
      StreamController<AudioPlaybackState>.broadcast();
  final Completer<void> _playCompleter = Completer<void>();
  final bool hangOnStop;
  final bool hangOnSeek;

  int playCalls = 0;
  int pauseCalls = 0;
  int seekCalls = 0;
  int setUrlCalls = 0;
  String? lastUrl;
  bool _playing = false;
  Duration _position = Duration.zero;
  final List<double> volumeChanges = [];
  final List<bool> equalizerEnabledChanges = [];
  final List<EqualizerBandGain> equalizerBandGainChanges = [];

  _FakeAudioController({this.hangOnStop = false, this.hangOnSeek = false});

  bool failOnSetVolume = false;

  /// 让 `play()` 以**异步**错误失败（用于测"换源流半途断"）。
  ///
  /// 必须是异步：状态（`sourcePlatform`）要先落位，随后才失败，那才是"换源成功
  /// 起播、播到一半断"的形状；同步抛出会被更早的 catch 吃掉，测不到这个时机。
  bool failPlayWithAsyncError = false;

  double _volume = 1.0;

  @override
  bool get playing => _playing;

  @override
  Duration get position => _position;

  @override
  double get volume => _volume;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<AudioPlaybackState> get playerStateStream =>
      _playerStateController.stream;

  @override
  Future<void> stop() async {
    if (hangOnStop) {
      return Completer<void>().future;
    }
    _playing = false;
  }

  @override
  Future<void> setUrl(String url) async {
    setUrlCalls++;
    lastUrl = url;
    _playerStateController.add(
      const AudioPlaybackState(
        playing: false,
        processingState: just_audio.ProcessingState.ready,
      ),
    );
  }

  @override
  Future<void> play() {
    playCalls++;
    if (failPlayWithAsyncError) {
      return Future<void>.error(StateError('play failed'));
    }
    _playing = true;
    _playerStateController.add(
      const AudioPlaybackState(
        playing: true,
        processingState: just_audio.ProcessingState.ready,
      ),
    );
    return _playCompleter.future;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _playing = false;
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
    if (hangOnSeek) {
      return Completer<void>().future;
    }
    _position = position;
  }

  @override
  Future<void> setVolume(double volume) async {
    if (failOnSetVolume) throw StateError('setVolume failed');
    _volume = volume;
    volumeChanges.add(volume);
  }

  void emitCompleted() {
    _playing = false;
    _playerStateController.add(
      const AudioPlaybackState(
        playing: false,
        processingState: just_audio.ProcessingState.completed,
      ),
    );
  }

  void emitPosition(Duration position) {
    _position = position;
    _positionController.add(position);
  }

  void emitDuration(Duration? duration) {
    _durationController.add(duration);
  }

  void emitState({
    required bool playing,
    required just_audio.ProcessingState processingState,
  }) {
    _playing = playing;
    _playerStateController.add(
      AudioPlaybackState(playing: playing, processingState: processingState),
    );
  }

  void emitError(Object error) {
    _playing = false;
    _playerStateController.addError(error);
  }

  @override
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> bandGains,
  }) async {
    equalizerEnabledChanges.add(enabled);
    for (var i = 0; i < bandGains.length; i++) {
      equalizerBandGainChanges.add(EqualizerBandGain(i, bandGains[i]));
    }
  }

  @override
  Future<void> dispose() async {
    await _positionController.close();
    await _durationController.close();
    await _playerStateController.close();
  }
}

class _FakeCapableAudioController extends _FakeAudioController
    implements PlaybackSpeedCapable, SkipSilenceCapable {
  final List<double> speedChanges = [];
  final List<bool> skipSilenceChanges = [];
  double _speed = 1.0;

  @override
  double get playbackSpeed => _speed;

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    _speed = speed;
    speedChanges.add(speed);
  }

  @override
  Future<void> setSkipSilence(bool enabled) async {
    skipSilenceChanges.add(enabled);
  }
}

/// `stop()` 的第一次调用永不返回，模拟"一个持锁操作被平台通道吊死"。
///
/// [stopGate] 在用例收尾时完成，让被吊住的 playSong 能正常收尾（不留悬空 timer）。
class _WedgingAudioController extends _FakeAudioController {
  final Completer<void> stopGate = Completer<void>();
  int stopCalls = 0;

  @override
  Future<void> stop() {
    stopCalls++;
    if (stopCalls == 1) return stopGate.future;
    return super.stop();
  }
}

/// dispose 需要一段真实时间，用来把两次重建触发点重叠在一起。
class _SlowDisposeAudioController extends _FakeAudioController {
  final Duration delay;
  int disposeCalls = 0;

  _SlowDisposeAudioController({
    super.hangOnStop,
    super.hangOnSeek,
    this.delay = const Duration(milliseconds: 150),
  });

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await Future<void>.delayed(delay);
    await super.dispose();
  }
}

/// getSongUrl 对指定歌曲直接失败（用来制造"恢复取流失败"）。
class _ErroringUrlPlatform extends _FakeMusicPlatform {
  final Set<String> failingIds;

  _ErroringUrlPlatform({required this.failingIds});

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) {
    requestedQualities.add((songId: songId, quality: quality));
    if (failingIds.contains(songId)) {
      return Future.error(StateError('url unavailable'));
    }
    return Future.value('https://example.test/$songId-${quality.name}.mp3');
  }
}

/// 第 2 次请求 [AudioLevel.high] 时失败：用来驱动"降一档音质"重试。
///
/// 第 1 次让 [PlayerNotifier.switchQuality] 成功把当前音质抬到 high，第 2 次
/// （playSong 取流）失败，于是失败链必须退到 medium 才可能播出来。
class _FailingHighQualityPlatform extends _FakeMusicPlatform {
  int highRequests = 0;

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) {
    if (quality == AudioLevel.high) {
      highRequests++;
      if (highRequests > 1) {
        requestedQualities.add((songId: songId, quality: quality));
        return Future.error(StateError('high quality unavailable'));
      }
    }
    return super.getSongUrl(songId, quality: quality);
  }
}

class _FakePlaybackKeepAliveController implements PlaybackKeepAliveController {
  final List<bool> playingStates = [];
  final List<bool> forceStates = [];
  bool disposed = false;

  @override
  Future<void> setPlaying(bool playing, {bool force = false}) async {
    playingStates.add(playing);
    forceStates.add(force);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    playingStates.add(false);
  }
}

class _PlaybackNotificationUpdate {
  final Song? currentSong;
  final bool isCurrentSongLiked;
  final bool isPlaying;
  final Duration duration;

  const _PlaybackNotificationUpdate({
    required this.currentSong,
    required this.isCurrentSongLiked,
    required this.isPlaying,
    required this.duration,
  });
}

class _FakePlaybackNotificationController
    implements PlaybackNotificationController {
  final List<_PlaybackNotificationUpdate> updates = [];
  bool attached = false;
  bool detached = false;
  PlaybackNotificationActions? actions;

  @override
  Future<void> initialize({DiagnosticsService? diagnostics}) async {}

  @override
  void attach(PlaybackNotificationActions actions) {
    attached = true;
    this.actions = actions;
  }

  @override
  void detach() {
    detached = true;
  }

  @override
  void update({
    required Song? currentSong,
    required List<Song> playlist,
    required int currentIndex,
    required bool isCurrentSongLiked,
    required bool isFloatingLyricsEnabled,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) {
    updates.add(
      _PlaybackNotificationUpdate(
        currentSong: currentSong,
        isCurrentSongLiked: isCurrentSongLiked,
        isPlaying: isPlaying,
        duration: duration,
      ),
    );
  }
}

class _MemoryPlaybackStore implements PlayerPlaybackMemoryStore {
  PlayerPlaybackMemory? restored;
  PlayerPlaybackMemory? saved;
  bool cleared = false;

  _MemoryPlaybackStore({this.restored});

  @override
  Future<PlayerPlaybackMemory?> load() async => restored;

  @override
  Future<void> save(PlayerPlaybackMemory memory) async {
    saved = memory;
  }

  @override
  Future<void> clear() async {
    cleared = true;
    saved = null;
    restored = null;
  }
}

class _FakeMusicPlatform extends MusicPlatform {
  final Map<String, List<AudioQuality>> qualitiesBySong;
  final List<({String songId, AudioLevel quality})> requestedQualities = [];
  final List<String> availableQualityRequests = [];

  _FakeMusicPlatform({this.qualitiesBySong = const {}});

  List<AudioLevel> requestedQualitiesFor(String songId) => requestedQualities
      .where((request) => request.songId == songId)
      .map((request) => request.quality)
      .toList();

  @override
  PlatformType get platformType => PlatformType.netease;

  @override
  String get platformName => 'fake';

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> saveSession(SessionStorage storage) async {}

  @override
  Future<void> restoreSession(SessionStorage storage) async {}

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) async {
    requestedQualities.add((songId: songId, quality: quality));
    return 'https://example.test/$songId-${quality.name}.mp3';
  }

  @override
  Future<List<AudioQuality>> getAvailableQualities(String songId) async {
    availableQualityRequests.add(songId);
    return qualitiesBySong[songId] ?? const [];
  }

  @override
  Future<QrLoginResult> getQrCode() {
    throw UnimplementedError();
  }

  @override
  Stream<QrLoginStatus> pollQrStatus(String key) {
    throw UnimplementedError();
  }

  @override
  Future<LoginResult> loginByPhone(String phone, String code) {
    throw UnimplementedError();
  }

  @override
  Future<LoginResult> sendPhoneCode(String phone) async =>
      const LoginResult(success: false, error: 'unsupported');

  @override
  Future<User?> getUserInfo() async => null;

  @override
  Future<void> logout() async {}

  @override
  Future<List<Song>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async => const [];

  @override
  Future<List<Playlist>> searchPlaylists(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async => const [];

  @override
  Future<String?> getLyrics(String songId) async => null;

  @override
  Future<List<Playlist>> getUserPlaylists() async => const [];

  @override
  Future<List<Song>> getPlaylistDetail(String playlistId) async => const [];

  @override
  Future<List<Song>> getLikedSongs() async => const [];

  @override
  Future<bool> likeSong(String songId, {bool like = true}) async => false;

  @override
  Future<bool> addSongToPlaylist(String playlistId, Song song) async => false;

  @override
  Future<Playlist?> createPlaylist(String name) async => null;

  @override
  Future<bool> collectPlaylist(
    String playlistId, {
    bool collect = true,
  }) async => false;

  @override
  Future<List<Song>> getDailyRecommendations() async => const [];

  @override
  Future<List<Song>> getRankingList() async => const [];

  @override
  Future<VipLevel> getVipStatus() async => VipLevel.free;

  @override
  Future<Playlist?> parseShareLink(String url) async => null;
}

class _QualityHangPlatform extends _FakeMusicPlatform {
  final String normalUrl;
  final Completer<String> qualityCompleter;

  _QualityHangPlatform({
    required this.normalUrl,
    required this.qualityCompleter,
  });

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) {
    if (quality == AudioLevel.lossless) {
      return qualityCompleter.future;
    }
    return Future.value(normalUrl);
  }
}

/// `getSongUrl` hangs on every 'stall-a' request after the first one, so the
/// stall-recovery sequence is forced to sit inside `_AudioMutex`.
class _RecoveryHangPlatform extends _FakeMusicPlatform {
  final Completer<String> recoveryCompleter;
  final List<String> requestedSongIds = [];
  int _stallCalls = 0;

  _RecoveryHangPlatform({required this.recoveryCompleter});

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) {
    requestedSongIds.add(songId);
    if (songId == 'stall-a') {
      _stallCalls++;
      if (_stallCalls > 1) return recoveryCompleter.future;
    }
    return super.getSongUrl(songId, quality: quality);
  }
}

class _ControlledUrlPlatform extends _FakeMusicPlatform {
  final Map<String, Future<String>> urls;

  _ControlledUrlPlatform({required this.urls});

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) {
    final url = urls[songId];
    if (url != null) return url;
    return super.getSongUrl(songId, quality: quality);
  }
}
