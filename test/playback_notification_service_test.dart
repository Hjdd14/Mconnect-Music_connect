import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
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
}

Song _song(String id, {String? name}) => Song(
  id: id,
  platform: PlatformType.netease,
  name: name ?? 'song $id',
  artists: const [Artist(id: 'artist', name: 'artist')],
);
