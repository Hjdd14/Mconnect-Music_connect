import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

void main() {
  test('builds compact Android controls with previous, play/pause, next', () {
    final playing = buildPlaybackNotificationState(
      hasCurrentSong: true,
      isPlaying: true,
      position: const Duration(seconds: 12),
      duration: const Duration(minutes: 3),
      queueIndex: 1,
    );

    expect(playing.controls, [
      MediaControl.skipToPrevious,
      MediaControl.pause,
      MediaControl.skipToNext,
    ]);
    expect(playing.androidCompactActionIndices, [0, 1, 2]);
    expect(playing.systemActions, contains(MediaAction.seek));
    expect(playing.playing, isTrue);
    expect(playing.queueIndex, 1);

    final paused = buildPlaybackNotificationState(
      hasCurrentSong: true,
      isPlaying: false,
      position: const Duration(seconds: 12),
      duration: const Duration(minutes: 3),
      queueIndex: 1,
    );

    expect(paused.controls[1], MediaControl.play);
    expect(paused.playing, isFalse);
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
    Duration? seekPosition;
    final handler = MconnectAudioHandler();

    handler.attach(
      PlaybackNotificationActions(
        play: () async => playCalls++,
        pause: () async => pauseCalls++,
        skipToNext: () async => nextCalls++,
        skipToPrevious: () async => previousCalls++,
        seek: (position) async => seekPosition = position,
      ),
    );

    await handler.play();
    await handler.pause();
    await handler.skipToNext();
    await handler.skipToPrevious();
    await handler.seek(const Duration(seconds: 25));

    expect(playCalls, 1);
    expect(pauseCalls, 1);
    expect(nextCalls, 1);
    expect(previousCalls, 1);
    expect(seekPosition, const Duration(seconds: 25));
  });

  test('handler publishes queue, media item and playback state', () {
    final handler = MconnectAudioHandler();
    final songs = [_song('1'), _song('2')];

    handler.updatePlayback(
      currentSong: songs[1],
      playlist: songs,
      currentIndex: 1,
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
}

Song _song(String id, {String? name}) => Song(
  id: id,
  platform: PlatformType.netease,
  name: name ?? 'song $id',
  artists: const [Artist(id: 'artist', name: 'artist')],
);

class _FakeHandlerAudioController implements PlayerAudioController {
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _playerStateController =
      StreamController<AudioPlaybackState>.broadcast();
  bool _playing = false;
  Duration _position = Duration.zero;

  @override
  bool get playing => _playing;

  @override
  Duration get position => _position;

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
