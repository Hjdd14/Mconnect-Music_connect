import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/platform/platform_utils.dart';
import '../../../models/song.dart';

typedef PlaybackCommand = Future<void> Function();
typedef PlaybackSeekCommand = Future<void> Function(Duration position);

class PlaybackNotificationActions {
  final PlaybackCommand play;
  final PlaybackCommand pause;
  final PlaybackCommand skipToNext;
  final PlaybackCommand skipToPrevious;
  final PlaybackSeekCommand seek;

  const PlaybackNotificationActions({
    required this.play,
    required this.pause,
    required this.skipToNext,
    required this.skipToPrevious,
    required this.seek,
  });
}

abstract class PlaybackNotificationController {
  Future<void> initialize({DiagnosticsService? diagnostics});

  void attach(PlaybackNotificationActions actions);

  void detach();

  void update({
    required Song? currentSong,
    required List<Song> playlist,
    required int currentIndex,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  });
}

class AudioServicePlaybackNotificationController
    implements PlaybackNotificationController {
  AudioServicePlaybackNotificationController._();

  static final AudioServicePlaybackNotificationController instance =
      AudioServicePlaybackNotificationController._();

  final MconnectAudioHandler _handler = MconnectAudioHandler();
  bool _initialized = false;

  @override
  Future<void> initialize({DiagnosticsService? diagnostics}) async {
    if (!PlatformUtils.isAndroid || _initialized) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await AudioService.init(
        builder: () => _handler,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.mconnect.mconnect.audio',
          androidNotificationChannelName: 'Mconnect playback',
          androidNotificationIcon: 'mipmap/ic_launcher',
          androidStopForegroundOnPause: false,
        ),
      );
      _initialized = true;
    } catch (error, stack) {
      debugPrint('PlaybackNotificationService initialize failed: $error');
      diagnostics?.recordError(
        'playback_notification.initialize',
        error,
        stack,
      );
    }
  }

  @override
  void attach(PlaybackNotificationActions actions) {
    _handler.attach(actions);
  }

  @override
  void detach() {
    _handler.detach();
  }

  @override
  void update({
    required Song? currentSong,
    required List<Song> playlist,
    required int currentIndex,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) {
    _handler.updatePlayback(
      currentSong: currentSong,
      playlist: playlist,
      currentIndex: currentIndex,
      isPlaying: isPlaying,
      position: position,
      duration: duration,
    );
  }
}

@visibleForTesting
class MconnectAudioHandler extends BaseAudioHandler with SeekHandler {
  PlaybackNotificationActions? _actions;

  void attach(PlaybackNotificationActions actions) {
    _actions = actions;
  }

  void detach() {
    _actions = null;
  }

  void updatePlayback({
    required Song? currentSong,
    required List<Song> playlist,
    required int currentIndex,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) {
    final hasCurrentSong = currentSong != null;
    final effectivePlaylist = hasCurrentSong
        ? _normalizePlaylist(currentSong, playlist)
        : const <Song>[];
    final effectiveIndex = hasCurrentSong
        ? _normalizeCurrentIndex(currentSong, effectivePlaylist, currentIndex)
        : -1;

    queue.add(buildPlaybackNotificationQueue(effectivePlaylist));
    mediaItem.add(hasCurrentSong ? createPlaybackMediaItem(currentSong) : null);
    playbackState.add(
      buildPlaybackNotificationState(
        hasCurrentSong: hasCurrentSong,
        isPlaying: isPlaying,
        position: position,
        duration: duration,
        queueIndex: effectiveIndex,
      ),
    );
  }

  @override
  Future<void> play() async {
    await _actions?.play();
  }

  @override
  Future<void> pause() async {
    await _actions?.pause();
  }

  @override
  Future<void> skipToNext() async {
    await _actions?.skipToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await _actions?.skipToPrevious();
  }

  @override
  Future<void> seek(Duration position) async {
    await _actions?.seek(position);
  }

  @override
  Future<void> stop() async {
    await _actions?.pause();
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      ),
    );
  }
}

@visibleForTesting
List<MediaItem> buildPlaybackNotificationQueue(List<Song> playlist) {
  return playlist.map(createPlaybackMediaItem).toList(growable: false);
}

@visibleForTesting
PlaybackState buildPlaybackNotificationState({
  required bool hasCurrentSong,
  required bool isPlaying,
  required Duration position,
  required Duration duration,
  required int queueIndex,
}) {
  final primaryControl = isPlaying ? MediaControl.pause : MediaControl.play;
  final controls = hasCurrentSong
      ? <MediaControl>[
          MediaControl.skipToPrevious,
          primaryControl,
          MediaControl.skipToNext,
        ]
      : <MediaControl>[primaryControl];

  return PlaybackState(
    controls: controls,
    systemActions: const {
      MediaAction.seek,
      MediaAction.skipToPrevious,
      MediaAction.skipToNext,
    },
    androidCompactActionIndices: List<int>.generate(
      controls.length,
      (index) => index,
    ),
    processingState: hasCurrentSong
        ? AudioProcessingState.ready
        : AudioProcessingState.idle,
    playing: isPlaying,
    updatePosition: position,
    bufferedPosition: duration,
    queueIndex: hasCurrentSong && queueIndex >= 0 ? queueIndex : null,
  );
}

MediaItem createPlaybackMediaItem(Song song, {String? sourceUrl}) {
  final artist = song.artistNames.trim();
  final artUri = _parseOptionalUri(song.coverUrl ?? song.album?.coverUrl);
  return MediaItem(
    id: '${song.platform.name}:${song.id}',
    title: song.name,
    album: song.album?.name,
    artist: artist.isEmpty ? null : artist,
    duration: song.duration == Duration.zero ? null : song.duration,
    artUri: artUri,
    extras: {
      'platform': song.platform.name,
      'songId': song.id,
      'sourceUrl': ?sourceUrl,
    },
  );
}

MediaItem createFallbackPlaybackMediaItem(String url) {
  return MediaItem(id: url, title: 'Mconnect');
}

List<Song> _normalizePlaylist(Song currentSong, List<Song> playlist) {
  if (playlist.isEmpty) return [currentSong];
  final hasCurrentSong = playlist.any((song) => _sameSong(song, currentSong));
  if (hasCurrentSong) return playlist;
  return [...playlist, currentSong];
}

int _normalizeCurrentIndex(
  Song currentSong,
  List<Song> playlist,
  int currentIndex,
) {
  if (currentIndex >= 0 &&
      currentIndex < playlist.length &&
      _sameSong(playlist[currentIndex], currentSong)) {
    return currentIndex;
  }
  return playlist.indexWhere((song) => _sameSong(song, currentSong));
}

bool _sameSong(Song a, Song b) {
  return a.id == b.id && a.platform == b.platform;
}

Uri? _parseOptionalUri(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return null;
  return uri;
}
