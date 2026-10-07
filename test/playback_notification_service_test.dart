import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:mconnect/core/diagnostics/diagnostics_service.dart';
import 'package:mconnect/features/player/data/audio_focus_diagnostics.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

void main() {
  test('builds compact Android controls with previous, play/pause, next', () {
    final playing = buildPlaybackNotificationState(
      hasCurrentSong: true,
      isCurrentSongLiked: false,
      isFloatingLyricsEnabled: false,
      isPlaying: true,
      position: const Duration(seconds: 12),
      duration: const Duration(minutes: 3),
      queueIndex: 1,
    );

    expect(playing.controls, [
      MediaControl.skipToPrevious,
      MediaControl.pause,
      MediaControl.skipToNext,
      isA<MediaControl>()
          .having(
            (control) => control.customAction?.name,
            'name',
            'like_current_song',
          )
          .having(
            (control) => control.androidIcon,
            'icon',
            'drawable/audio_service_favorite_outline',
          ),
      isA<MediaControl>()
          .having(
            (control) => control.customAction?.name,
            'name',
            'toggle_floating_lyrics',
          )
          .having(
            (control) => control.androidIcon,
            'icon',
            'drawable/audio_service_lyrics_off',
          ),
    ]);
    expect(playing.androidCompactActionIndices, [0, 1, 2]);
    expect(playing.systemActions, contains(MediaAction.seek));
    expect(playing.playing, isTrue);
    expect(playing.queueIndex, 1);

    final paused = buildPlaybackNotificationState(
      hasCurrentSong: true,
      isCurrentSongLiked: false,
      isFloatingLyricsEnabled: false,
      isPlaying: false,
      position: const Duration(seconds: 12),
      duration: const Duration(minutes: 3),
      queueIndex: 1,
    );

    expect(paused.controls[1], MediaControl.play);
    expect(paused.playing, isFalse);
  });

  test('builds filled favorite control when current song is liked', () {
    final liked = buildPlaybackNotificationState(
      hasCurrentSong: true,
      isCurrentSongLiked: true,
      isFloatingLyricsEnabled: false,
      isPlaying: false,
      position: const Duration(seconds: 12),
      duration: const Duration(minutes: 3),
      queueIndex: 0,
    );

    final favorite = liked.controls.firstWhere(
      (control) => control.customAction?.name == 'like_current_song',
    );
    expect(favorite.androidIcon, 'drawable/audio_service_favorite_filled');
    expect(liked.androidCompactActionIndices, [0, 1, 2]);

    final noSong = buildPlaybackNotificationState(
      hasCurrentSong: false,
      isCurrentSongLiked: false,
      isFloatingLyricsEnabled: false,
      isPlaying: false,
      position: Duration.zero,
      duration: Duration.zero,
      queueIndex: -1,
    );

    expect(
      noSong.controls.any(
        (control) => control.customAction?.name == 'like_current_song',
      ),
      isFalse,
    );
    expect(
      noSong.controls.any(
        (control) => control.customAction?.name == 'toggle_floating_lyrics',
      ),
      isFalse,
    );
    expect(noSong.androidCompactActionIndices, [0]);
  });

  test('lyrics control mirrors the floating lyrics switch', () {
    final off = buildPlaybackNotificationState(
      hasCurrentSong: true,
      isCurrentSongLiked: false,
      isFloatingLyricsEnabled: false,
      isPlaying: true,
      position: Duration.zero,
      duration: const Duration(minutes: 3),
      queueIndex: 0,
    );
    final offControl = off.controls.firstWhere(
      (control) => control.customAction?.name == 'toggle_floating_lyrics',
    );
    expect(offControl.androidIcon, 'drawable/audio_service_lyrics_off');
    expect(offControl.label, '歌词');

    final on = buildPlaybackNotificationState(
      hasCurrentSong: true,
      isCurrentSongLiked: false,
      isFloatingLyricsEnabled: true,
      isPlaying: true,
      position: Duration.zero,
      duration: const Duration(minutes: 3),
      queueIndex: 0,
    );
    final onControl = on.controls.firstWhere(
      (control) => control.customAction?.name == 'toggle_floating_lyrics',
    );
    expect(onControl.androidIcon, 'drawable/audio_service_lyrics_on');
    expect(onControl.label, '关闭歌词');
  });

  test('maps playlist songs to media items for system queue', () {
    final queue = buildPlaybackNotificationQueue([
      _song('1', name: 'first'),
      _song('2', name: 'second'),
    ]);

    expect(queue, hasLength(2));
    expect(queue[0].id, 'netease:1');
    expect(queue[0].title, 'first');
    expect(queue[0].artist, 'artist');
    expect(queue[1].id, 'netease:2');
  });

  test('handler forwards notification commands to player callbacks', () async {
    var playCalls = 0;
    var pauseCalls = 0;
    var nextCalls = 0;
    var previousCalls = 0;
    var likeCalls = 0;
    var lyricsCalls = 0;
    Duration? seekPosition;
    final handler = MconnectAudioHandler();

    handler.attach(
      PlaybackNotificationActions(
        play: () async => playCalls++,
        pause: () async => pauseCalls++,
        skipToNext: () async => nextCalls++,
        skipToPrevious: () async => previousCalls++,
        seek: (position) async => seekPosition = position,
        toggleLikeCurrentSong: () async => likeCalls++,
        toggleFloatingLyrics: () async => lyricsCalls++,
      ),
    );

    await handler.play();
    await handler.pause();
    await handler.skipToNext();
    await handler.skipToPrevious();
    await handler.seek(const Duration(seconds: 25));
    await handler.customAction('like_current_song');
    await handler.customAction('toggle_floating_lyrics');

    expect(playCalls, 1);
    expect(pauseCalls, 1);
    expect(nextCalls, 1);
    expect(previousCalls, 1);
    expect(seekPosition, const Duration(seconds: 25));
    expect(likeCalls, 1);
    expect(lyricsCalls, 1);
  });

  test('handler publishes queue, media item and playback state', () {
    final handler = MconnectAudioHandler();
    final songs = [_song('1'), _song('2')];

    handler.updatePlayback(
      currentSong: songs[1],
      playlist: songs,
      currentIndex: 1,
      isCurrentSongLiked: false,
      isFloatingLyricsEnabled: true,
      isPlaying: true,
      position: const Duration(seconds: 8),
      duration: const Duration(minutes: 4),
    );

    expect(handler.queue.value.map((item) => item.id), [
      'netease:1',
      'netease:2',
    ]);
    expect(handler.mediaItem.value?.id, 'netease:2');
    expect(handler.playbackState.value.controls, [
      MediaControl.skipToPrevious,
      MediaControl.pause,
      MediaControl.skipToNext,
      isA<MediaControl>()
          .having(
            (control) => control.customAction?.name,
            'name',
            'like_current_song',
          )
          .having(
            (control) => control.androidIcon,
            'icon',
            'drawable/audio_service_favorite_outline',
          ),
      isA<MediaControl>()
          .having(
            (control) => control.customAction?.name,
            'name',
            'toggle_floating_lyrics',
          )
          .having(
            (control) => control.androidIcon,
            'icon',
            'drawable/audio_service_lyrics_on',
          ),
    ]);
    expect(handler.playbackState.value.queueIndex, 1);
  });

  test(
    'handler publishes playback state from the bound audio controller',
    () async {
      final handler = MconnectAudioHandler();
      final audio = _FakeHandlerAudioController();
      final songs = [_song('1'), _song('2')];

      (handler as dynamic).bindAudioController(audio);
      handler.updatePlayback(
        currentSong: songs[1],
        playlist: songs,
        currentIndex: 1,
        isCurrentSongLiked: true,
        isFloatingLyricsEnabled: false,
        isPlaying: false,
        position: Duration.zero,
        duration: const Duration(minutes: 4),
      );

      audio.emitState(
        playing: true,
        processingState: just_audio.ProcessingState.buffering,
      );
      audio.emitPosition(const Duration(seconds: 42));
      audio.emitDuration(const Duration(minutes: 4));
      await pumpEventQueue();

      expect(handler.playbackState.value.playing, isTrue);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.buffering,
      );
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(seconds: 42),
      );
      expect(handler.playbackState.value.queueIndex, 1);

      handler.updatePlayback(
        currentSong: songs[1],
        playlist: songs,
        currentIndex: 1,
        isCurrentSongLiked: true,
        isFloatingLyricsEnabled: false,
        isPlaying: false,
        position: Duration.zero,
        duration: const Duration(minutes: 4),
      );

      expect(handler.playbackState.value.playing, isTrue);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.buffering,
      );
    },
  );

  test(
    'handler update can restore canonical app playback while audio is bound',
    () async {
      final handler = MconnectAudioHandler();
      final audio = _FakeHandlerAudioController();
      final song = _song('canonical', duration: Duration.zero);

      (handler as dynamic).bindAudioController(audio);
      handler.updatePlayback(
        currentSong: song,
        playlist: [song],
        currentIndex: 0,
        isCurrentSongLiked: false,
        isFloatingLyricsEnabled: false,
        isPlaying: true,
        position: const Duration(seconds: 12),
        duration: const Duration(minutes: 3),
      );

      audio.emitState(
        playing: false,
        processingState: just_audio.ProcessingState.loading,
      );
      audio.emitDuration(Duration.zero);
      await pumpEventQueue();

      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.mediaItem.value?.duration, const Duration(minutes: 3));

      handler.updatePlayback(
        currentSong: song,
        playlist: [song],
        currentIndex: 0,
        isCurrentSongLiked: false,
        isFloatingLyricsEnabled: false,
        isPlaying: true,
        position: const Duration(seconds: 12),
        duration: const Duration(minutes: 3),
      );

      expect(handler.playbackState.value.playing, isTrue);
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(seconds: 12),
      );
      expect(
        handler.playbackState.value.bufferedPosition,
        const Duration(minutes: 3),
      );
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.ready,
      );
      expect(handler.mediaItem.value?.duration, const Duration(minutes: 3));
    },
  );

  group('notification update de-duplication (ANR fix)', () {
    // `updatePlayback` runs on every `_setState`: several times per `playSong`
    // and about once a second per position tick. Republishing the whole queue and
    // media item on each of those made Android rebuild the notification on the
    // main thread. These tests pin the two tiers: structural work only when
    // something really changed, and a throttled lightweight broadcast otherwise.

    test('ten position-only updates publish the structure exactly once', () async {
      final handler = MconnectAudioHandler();
      final queueAdds = _EmissionCounter(handler.queue);
      final itemAdds = _EmissionCounter(handler.mediaItem);
      await _armCounters([queueAdds, itemAdds]);
      final songs = [_song('1'), _song('2')];

      // The playlist instance is reused on purpose: that is what
      // `player_provider` passes for position ticks.
      handler.updatePlayback(
        currentSong: songs[1],
        playlist: songs,
        currentIndex: 1,
        isCurrentSongLiked: false,
        isFloatingLyricsEnabled: false,
        isPlaying: true,
        position: const Duration(seconds: 8),
        duration: const Duration(minutes: 4),
      );

      for (var tick = 1; tick <= 10; tick++) {
        handler.updatePlayback(
          currentSong: songs[1],
          playlist: songs,
          currentIndex: 1,
          isCurrentSongLiked: false,
          isFloatingLyricsEnabled: false,
          isPlaying: true,
          position: Duration(milliseconds: 8000 + tick * 100),
          duration: const Duration(minutes: 4),
        );
      }
      await pumpEventQueue();

      expect(
        queueAdds.count,
        1,
        reason: 'a position tick must not rebuild the MediaItem queue',
      );
      expect(itemAdds.count, 1);
      expect(handler.playbackState.value.updatePosition, isNot(Duration.zero));

      await queueAdds.dispose();
      await itemAdds.dispose();
    });

    test('switching song publishes one new structure with the new item', () async {
      final handler = MconnectAudioHandler();
      final queueAdds = _EmissionCounter(handler.queue);
      final itemAdds = _EmissionCounter(handler.mediaItem);
      await _armCounters([queueAdds, itemAdds]);
      final songs = [_song('1', name: 'first'), _song('2', name: 'second')];

      handler.updatePlayback(
        currentSong: songs[0],
        playlist: songs,
        currentIndex: 0,
        isCurrentSongLiked: false,
        isFloatingLyricsEnabled: false,
        isPlaying: true,
        position: Duration.zero,
        duration: const Duration(minutes: 4),
      );
      await pumpEventQueue();
      final queueAfterFirst = queueAdds.count;
      final itemAfterFirst = itemAdds.count;

      handler.updatePlayback(
        currentSong: songs[1],
        playlist: songs,
        currentIndex: 1,
        isCurrentSongLiked: false,
        isFloatingLyricsEnabled: false,
        isPlaying: true,
        position: Duration.zero,
        duration: const Duration(minutes: 4),
      );
      await pumpEventQueue();

      expect(queueAdds.count - queueAfterFirst, 1);
      expect(itemAdds.count - itemAfterFirst, 1);
      expect(handler.mediaItem.value?.id, 'netease:2');
      expect(handler.mediaItem.value?.title, 'second');
      expect(handler.playbackState.value.queueIndex, 1);

      await queueAdds.dispose();
      await itemAdds.dispose();
    });

    test('play/pause does not rebuild the structure but updates playback state', () async {
      final handler = MconnectAudioHandler();
      final queueAdds = _EmissionCounter(handler.queue);
      final itemAdds = _EmissionCounter(handler.mediaItem);
      final stateAdds = _EmissionCounter(handler.playbackState);
      await _armCounters([queueAdds, itemAdds, stateAdds]);
      final song = _song('1');

      handler.updatePlayback(
        currentSong: song,
        playlist: [song],
        currentIndex: 0,
        isCurrentSongLiked: false,
        isFloatingLyricsEnabled: false,
        isPlaying: true,
        position: const Duration(seconds: 5),
        duration: const Duration(minutes: 4),
      );
      await pumpEventQueue();
      final queueBaseline = queueAdds.count;
      final itemBaseline = itemAdds.count;

      handler.updatePlayback(
        currentSong: song,
        playlist: [song],
        currentIndex: 0,
        isCurrentSongLiked: false,
        isFloatingLyricsEnabled: false,
        isPlaying: false,
        position: const Duration(seconds: 5),
        duration: const Duration(minutes: 4),
      );
      await pumpEventQueue();

      expect(
        queueAdds.count,
        queueBaseline,
        reason: 'the play/pause button lives in playbackState, not in the queue',
      );
      expect(itemAdds.count, itemBaseline);
      expect(handler.playbackState.value.playing, isFalse);

      await queueAdds.dispose();
      await itemAdds.dispose();
      await stateAdds.dispose();
    });

    test('liked and floating lyrics changes each publish once', () async {
      final handler = MconnectAudioHandler();
      final queueAdds = _EmissionCounter(handler.queue);
      await _armCounters([queueAdds]);
      final song = _song('1');

      handler.updatePlayback(
        currentSong: song,
        playlist: [song],
        currentIndex: 0,
        isCurrentSongLiked: false,
        isFloatingLyricsEnabled: false,
        isPlaying: true,
        position: Duration.zero,
        duration: const Duration(minutes: 4),
      );
      await pumpEventQueue();
      final baseline = queueAdds.count;

      handler.updatePlayback(
        currentSong: song,
        playlist: [song],
        currentIndex: 0,
        isCurrentSongLiked: true,
        isFloatingLyricsEnabled: false,
        isPlaying: true,
        position: Duration.zero,
        duration: const Duration(minutes: 4),
      );
      await pumpEventQueue();
      expect(queueAdds.count - baseline, 1);
      final favorite = handler.playbackState.value.controls.firstWhere(
        (control) => control.customAction?.name == playbackNotificationLikeAction,
      );
      expect(favorite.androidIcon, 'drawable/audio_service_favorite_filled');

      handler.updatePlayback(
        currentSong: song,
        playlist: [song],
        currentIndex: 0,
        isCurrentSongLiked: true,
        isFloatingLyricsEnabled: true,
        isPlaying: true,
        position: Duration.zero,
        duration: const Duration(minutes: 4),
      );
      await pumpEventQueue();
      expect(queueAdds.count - baseline, 2);
      final lyrics = handler.playbackState.value.controls.firstWhere(
        (control) => control.customAction?.name == playbackNotificationLyricsAction,
      );
      expect(lyrics.androidIcon, 'drawable/audio_service_lyrics_on');

      // Repeating the same flags is not a change.
      handler.updatePlayback(
        currentSong: song,
        playlist: [song],
        currentIndex: 0,
        isCurrentSongLiked: true,
        isFloatingLyricsEnabled: true,
        isPlaying: true,
        position: Duration.zero,
        duration: const Duration(minutes: 4),
      );
      await pumpEventQueue();
      expect(queueAdds.count - baseline, 2);

      await queueAdds.dispose();
    });

    test('a same-length playlist with different content rebuilds the queue', () async {
      final handler = MconnectAudioHandler();
      final queueAdds = _EmissionCounter(handler.queue);
      await _armCounters([queueAdds]);
      final first = [_song('1'), _song('2')];

      handler.updatePlayback(
        currentSong: first[0],
        playlist: first,
        currentIndex: 0,
        isCurrentSongLiked: false,
        isFloatingLyricsEnabled: false,
        isPlaying: true,
        position: Duration.zero,
        duration: Duration.zero,
      );
      await pumpEventQueue();
      final baseline = queueAdds.count;

      // Same length, different songs: comparing only the length would miss this.
      final second = [_song('3'), _song('4')];
      handler.updatePlayback(
        currentSong: second[0],
        playlist: second,
        currentIndex: 0,
        isCurrentSongLiked: false,
        isFloatingLyricsEnabled: false,
        isPlaying: true,
        position: Duration.zero,
        duration: Duration.zero,
      );
      await pumpEventQueue();

      expect(queueAdds.count - baseline, 1);
      expect(handler.queue.value.map((item) => item.id), [
        'netease:3',
        'netease:4',
      ]);

      await queueAdds.dispose();
    });

    test('a rebuilt-but-equal playlist does not rebuild the queue', () async {
      final handler = MconnectAudioHandler();
      final queueAdds = _EmissionCounter(handler.queue);
      await _armCounters([queueAdds]);

      // Fresh list instances with the same content — the discriminators
      // (identity, length, ends) say "unchanged", which is what keeps the
      // once-a-second update path free.
      for (var i = 0; i < 3; i++) {
        final playlist = [_song('1'), _song('2')];
        handler.updatePlayback(
          currentSong: playlist[0],
          playlist: playlist,
          currentIndex: 0,
          isCurrentSongLiked: false,
          isFloatingLyricsEnabled: false,
          isPlaying: true,
          position: Duration.zero,
          duration: Duration.zero,
        );
      }
      await pumpEventQueue();

      expect(queueAdds.count, 1);

      await queueAdds.dispose();
    });

    test('clearing the current song publishes an empty queue once', () async {
      final handler = MconnectAudioHandler();
      final queueAdds = _EmissionCounter(handler.queue);
      final itemAdds = _EmissionCounter(handler.mediaItem);
      await _armCounters([queueAdds, itemAdds]);
      final song = _song('1');

      handler.updatePlayback(
        currentSong: song,
        playlist: [song],
        currentIndex: 0,
        isCurrentSongLiked: false,
        isFloatingLyricsEnabled: false,
        isPlaying: true,
        position: Duration.zero,
        duration: Duration.zero,
      );
      await pumpEventQueue();
      final baseline = queueAdds.count;

      for (var i = 0; i < 3; i++) {
        handler.updatePlayback(
          currentSong: null,
          playlist: const [],
          currentIndex: -1,
          isCurrentSongLiked: false,
          isFloatingLyricsEnabled: false,
          isPlaying: false,
          position: Duration.zero,
          duration: Duration.zero,
        );
      }
      await pumpEventQueue();

      expect(queueAdds.count - baseline, 1);
      expect(handler.queue.value, isEmpty);
      expect(handler.mediaItem.value, isNull);
      expect(itemAdds.count, 2);
      expect(handler.playbackState.value.processingState, AudioProcessingState.idle);

      await queueAdds.dispose();
      await itemAdds.dispose();
    });

    test('small forward ticks are coalesced, a backwards seek is immediate', () async {
      final handler = MconnectAudioHandler();
      final stateAdds = _EmissionCounter(handler.playbackState);
      await _armCounters([stateAdds]);
      final song = _song('1');

      void update(Duration position) {
        handler.updatePlayback(
          currentSong: song,
          playlist: [song],
          currentIndex: 0,
          isCurrentSongLiked: false,
          isFloatingLyricsEnabled: false,
          isPlaying: true,
          position: position,
          duration: const Duration(minutes: 4),
        );
      }

      update(const Duration(seconds: 30));
      await pumpEventQueue();
      stateAdds.mark();

      // Sub-threshold forward movement: no republication.
      update(const Duration(milliseconds: 30200));
      await pumpEventQueue();
      expect(stateAdds.sinceMark, 0);

      // Past the threshold: the progress bar refreshes.
      update(const Duration(milliseconds: 31500));
      await pumpEventQueue();
      expect(stateAdds.sinceMark, 1);

      // A seek backwards is published at once, or the notification would keep
      // showing the old, further-ahead position.
      update(const Duration(seconds: 5));
      await pumpEventQueue();
      expect(stateAdds.sinceMark, 2);
      expect(
        handler.playbackState.value.updatePosition,
        const Duration(seconds: 5),
      );

      await stateAdds.dispose();
    });

    test('a duration that arrives late refreshes the item but not the queue', () async {
      final handler = MconnectAudioHandler();
      final queueAdds = _EmissionCounter(handler.queue);
      final itemAdds = _EmissionCounter(handler.mediaItem);
      await _armCounters([queueAdds, itemAdds]);
      final song = _song('1');

      handler.updatePlayback(
        currentSong: song,
        playlist: [song],
        currentIndex: 0,
        isCurrentSongLiked: false,
        isFloatingLyricsEnabled: false,
        isPlaying: true,
        position: Duration.zero,
        duration: Duration.zero,
      );
      await pumpEventQueue();
      final queueBaseline = queueAdds.count;

      // just_audio reports the real duration a moment after playback starts.
      handler.updatePlayback(
        currentSong: song,
        playlist: [song],
        currentIndex: 0,
        isCurrentSongLiked: false,
        isFloatingLyricsEnabled: false,
        isPlaying: true,
        position: const Duration(seconds: 1),
        duration: const Duration(minutes: 3),
      );
      await pumpEventQueue();

      expect(queueAdds.count, queueBaseline, reason: 'duration must not rebuild the queue');
      expect(handler.mediaItem.value?.duration, const Duration(minutes: 3));
      expect(itemAdds.count, 2);

      await queueAdds.dispose();
      await itemAdds.dispose();
    });
  });

  group('audio focus diagnostics', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mconnect_focus_diag_');
      await DiagnosticsService.instance.initializeForTest(tempDir);
    });

    tearDown(() async {
      await DiagnosticsService.instance.resetForTest();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('records interruption begin/end and becoming noisy events',
        () async {
          final interruptions =
              StreamController<AudioInterruptionEvent>.broadcast();
          final noisy = StreamController<void>.broadcast();
          final observer = AudioFocusDiagnosticsObserver(
            interruptionStream: interruptions.stream,
            becomingNoisyStream: noisy.stream,
          );
          observer.start();

          interruptions.add(
            AudioInterruptionEvent(true, AudioInterruptionType.pause),
          );
          interruptions.add(
            AudioInterruptionEvent(false, AudioInterruptionType.pause),
          );
          interruptions.add(
            AudioInterruptionEvent(true, AudioInterruptionType.duck),
          );
          noisy.add(null);
          await pumpEventQueue();

          final messages =
              DiagnosticsService.instance.recentEvents
                  .where((e) => e.type == 'audio_focus')
                  .map((e) => e.message)
                  .toList();
          expect(
            messages.any(
              (m) => m.contains('interruption_begin') && m.contains('pause'),
            ),
            isTrue,
          );
          expect(
            messages.any(
              (m) => m.contains('interruption_end') && m.contains('pause'),
            ),
            isTrue,
          );
          expect(
            messages.any(
              (m) => m.contains('interruption_begin') && m.contains('duck'),
            ),
            isTrue,
          );
          expect(messages.any((m) => m.contains('becoming_noisy')), isTrue);

          await observer.dispose();
        });

    test('stops logging after dispose', () async {
      final interruptions =
          StreamController<AudioInterruptionEvent>.broadcast();
      final noisy = StreamController<void>.broadcast();
      final observer = AudioFocusDiagnosticsObserver(
        interruptionStream: interruptions.stream,
        becomingNoisyStream: noisy.stream,
      );
      observer.start();
      await observer.dispose();

      interruptions.add(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      noisy.add(null);
      await pumpEventQueue();

      expect(
        DiagnosticsService.instance.recentEvents.where(
          (e) => e.type == 'audio_focus',
        ),
        isEmpty,
      );
    });
  });
}

/// Counts how often a handler stream actually published.
///
/// The handler's subjects are **seeded** `BehaviorSubject`s, so subscribing
/// replays the current value immediately; counting starts only after
/// [_armCounters], which lets that replay arrive first. Otherwise every test
/// would be off by one.
class _EmissionCounter {
  _EmissionCounter(Stream<Object?> stream) {
    _subscription = stream.listen((_) {
      if (_armed) count++;
    });
  }

  late final StreamSubscription<Object?> _subscription;
  bool _armed = false;
  int count = 0;

  /// Start counting from here.
  void mark() {
    _armed = true;
    count = 0;
  }

  int get sinceMark => count;

  Future<void> dispose() => _subscription.cancel();
}

/// Lets the seeded replay arrive, then arms [counters].
Future<void> _armCounters(List<_EmissionCounter> counters) async {
  await pumpEventQueue();
  for (final counter in counters) {
    counter.mark();
  }
}

Song _song(String id, {String? name, Duration duration = Duration.zero}) =>
    Song(
      id: id,
      platform: PlatformType.netease,
      name: name ?? 'song $id',
      duration: duration,
      artists: const [Artist(id: 'artist', name: 'artist')],
    );

class _FakeHandlerAudioController implements PlayerAudioController {
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _playerStateController =
      StreamController<AudioPlaybackState>.broadcast();
  bool _playing = false;
  final double _volume = 1.0;
  Duration _position = Duration.zero;

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

  void emitState({
    required bool playing,
    required just_audio.ProcessingState processingState,
  }) {
    _playing = playing;
    _playerStateController.add(
      AudioPlaybackState(playing: playing, processingState: processingState),
    );
  }

  void emitPosition(Duration position) {
    _position = position;
    _positionController.add(position);
  }

  void emitDuration(Duration duration) {
    _durationController.add(duration);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> setUrl(String url) async {}

  @override
  Future<void> play() async {
    emitState(playing: true, processingState: just_audio.ProcessingState.ready);
  }

  @override
  Future<void> pause() async {
    emitState(
      playing: false,
      processingState: just_audio.ProcessingState.ready,
    );
  }

  @override
  Future<void> seek(Duration position) async {
    emitPosition(position);
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> bandGains,
  }) async {}

  @override
  Future<void> dispose() async {
    await _positionController.close();
    await _durationController.close();
    await _playerStateController.close();
  }
}
