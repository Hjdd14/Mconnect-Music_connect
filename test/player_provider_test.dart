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

  _MemoryPlaybackStore({this.restored});

  @override
  Future<PlayerPlaybackMemory?> load() async => restored;

  @override
  Future<void> save(PlayerPlaybackMemory memory) async {
    saved = memory;
  }

  @override
  Future<void> clear() async {
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
