import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as just_audio;

import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/platform/platform_utils.dart';
import '../../../models/song.dart';
import 'player_audio_controller.dart';

typedef PlaybackCommand = Future<void> Function();
typedef PlaybackSeekCommand = Future<void> Function(Duration position);

const playbackNotificationLikeAction = 'like_current_song';

class PlaybackNotificationActions {
  final PlaybackCommand play;
  final PlaybackCommand pause;
  final PlaybackCommand skipToNext;
  final PlaybackCommand skipToPrevious;
  final PlaybackSeekCommand seek;
  final PlaybackCommand toggleLikeCurrentSong;

  const PlaybackNotificationActions({
    required this.play,
    required this.pause,
    required this.skipToNext,
    required this.skipToPrevious,
    required this.seek,
    required this.toggleLikeCurrentSong,
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
    required bool isCurrentSongLiked,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  });
}

class NoopPlaybackNotificationController
    implements PlaybackNotificationController {
  const NoopPlaybackNotificationController();

  @override
  Future<void> initialize({DiagnosticsService? diagnostics}) async {}

  @override
  void attach(PlaybackNotificationActions actions) {}

  @override
  void detach() {}

  @override
  void update({
    required Song? currentSong,
    required List<Song> playlist,
    required int currentIndex,
    required bool isCurrentSongLiked,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) {}
}

class AudioServicePlayerController
    implements PlaybackNotificationController, PlayerAudioController {
  AudioServicePlayerController._({
    MconnectAudioHandler? handler,
    PlayerAudioController Function()? audioControllerFactory,
  }) : _handler = handler ?? MconnectAudioHandler(),
       _audioControllerFactory =
           audioControllerFactory ?? (() => JustAudioController());

  static final AudioServicePlayerController instance =
      AudioServicePlayerController._();

  final MconnectAudioHandler _handler;
  final PlayerAudioController Function() _audioControllerFactory;
  PlayerAudioController? _audioController;
  bool _initialized = false;

  PlayerAudioController _ensureAudioController() {
    final existing = _audioController;
    if (existing != null) return existing;
    final controller = _audioControllerFactory();
    _audioController = controller;
    _handler.bindAudioController(controller);
    return controller;
  }

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
      diagnostics?.recordError('audio_service_player.initialize', error, stack);
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
    required bool isCurrentSongLiked,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) {
    _handler.updatePlayback(
      currentSong: currentSong,
      playlist: playlist,
      currentIndex: currentIndex,
      isCurrentSongLiked: isCurrentSongLiked,
      isPlaying: isPlaying,
      position: position,
      duration: duration,
    );
  }

  @override
  bool get playing => _ensureAudioController().playing;

  @override
  Duration get position => _ensureAudioController().position;

  @override
  Stream<Duration> get positionStream =>
      _ensureAudioController().positionStream;

  @override
  Stream<Duration?> get durationStream =>
      _ensureAudioController().durationStream;

  @override
  Stream<AudioPlaybackState> get playerStateStream =>
      _ensureAudioController().playerStateStream;

  @override
  Future<void> stop() => _ensureAudioController().stop();

  @override
  Future<void> setUrl(String url) => _ensureAudioController().setUrl(url);

  @override
  Future<void> play() => _ensureAudioController().play();

  @override
  Future<void> pause() => _ensureAudioController().pause();

  @override
  Future<void> seek(Duration position) =>
      _ensureAudioController().seek(position);

  @override
  Future<void> setVolume(double volume) =>
      _ensureAudioController().setVolume(volume);

  @override
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> bandGains,
  }) {
    return _ensureAudioController().applyEqualizer(
      enabled: enabled,
      bandGains: bandGains,
    );
  }

  @override
  Future<void> dispose() async {
    final controller = _audioController;
    _audioController = null;
    _handler.bindAudioController(null);
    await controller?.dispose();
  }
}

class AudioServicePlaybackNotificationController {
  static AudioServicePlayerController get instance =>
      AudioServicePlayerController.instance;
}

@visibleForTesting
class MconnectAudioHandler extends BaseAudioHandler with SeekHandler {
  PlaybackNotificationActions? _actions;
  PlayerAudioController? _audioController;
  final List<StreamSubscription> _audioSubscriptions = [];
  bool _hasCurrentSong = false;
  bool _playing = false;
  bool _isCurrentSongLiked = false;
  just_audio.ProcessingState _processingState = just_audio.ProcessingState.idle;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _queueIndex = -1;

  void attach(PlaybackNotificationActions actions) {
    _actions = actions;
  }

  void detach() {
    _actions = null;
  }

  void bindAudioController(PlayerAudioController? controller) {
    if (identical(_audioController, controller)) return;
    for (final sub in _audioSubscriptions) {
      unawaited(sub.cancel());
    }
    _audioSubscriptions.clear();
    _audioController = controller;
    if (controller == null) {
      _playing = false;
      _isCurrentSongLiked = false;
      _processingState = just_audio.ProcessingState.idle;
      _position = Duration.zero;
      _broadcastPlaybackState();
      return;
    }

    _playing = controller.playing;
    _position = controller.position;
    _audioSubscriptions.add(
      controller.playerStateStream.listen((state) {
        _playing = state.playing;
        _processingState = state.processingState;
        _broadcastPlaybackState();
      }),
    );
    _audioSubscriptions.add(
      controller.positionStream.listen((position) {
        _position = position;
        _broadcastPlaybackState();
      }),
    );
    _audioSubscriptions.add(
      controller.durationStream.listen((duration) {
        _duration = duration ?? Duration.zero;
        _broadcastPlaybackState();
      }),
    );
    _broadcastPlaybackState();
  }

  void updatePlayback({
    required Song? currentSong,
    required List<Song> playlist,
    required int currentIndex,
    required bool isCurrentSongLiked,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) {
    final song = currentSong;
    _hasCurrentSong = song != null;
    final List<Song> effectivePlaylist;
    final int effectiveIndex;
    if (song == null) {
      effectivePlaylist = const <Song>[];
      effectiveIndex = -1;
    } else {
      effectivePlaylist = _normalizePlaylist(song, playlist);
      effectiveIndex = _normalizeCurrentIndex(
        song,
        effectivePlaylist,
        currentIndex,
      );
    }
    _queueIndex = effectiveIndex;
    _isCurrentSongLiked = song != null && isCurrentSongLiked;
    _duration = duration;
    if (_audioController == null || isPlaying) {
      _playing = isPlaying;
      _position = position;
      _processingState = _hasCurrentSong
          ? just_audio.ProcessingState.ready
          : just_audio.ProcessingState.idle;
    }

    queue.add(buildPlaybackNotificationQueue(effectivePlaylist));
    mediaItem.add(
      song == null ? null : createPlaybackMediaItem(song, duration: _duration),
    );
    _broadcastPlaybackState();
  }

  void _broadcastPlaybackState() {
    playbackState.add(
      buildPlaybackNotificationState(
        hasCurrentSong: _hasCurrentSong,
        isPlaying: _playing,
        isCurrentSongLiked: _isCurrentSongLiked,
        position: _position,
        duration: _duration,
        queueIndex: _queueIndex,
        processingState: _mapProcessingState(
          _processingState,
          hasCurrentSong: _hasCurrentSong,
        ),
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
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == playbackNotificationLikeAction) {
      await _actions?.toggleLikeCurrentSong();
      return null;
    }
    return super.customAction(name, extras);
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
  required bool isCurrentSongLiked,
  required bool isPlaying,
  required Duration position,
  required Duration duration,
  required int queueIndex,
  AudioProcessingState? processingState,
}) {
  final primaryControl = isPlaying ? MediaControl.pause : MediaControl.play;
  final controls = hasCurrentSong
      ? <MediaControl>[
          MediaControl.skipToPrevious,
          primaryControl,
          MediaControl.skipToNext,
          _favoriteControl(isCurrentSongLiked),
        ]
      : <MediaControl>[primaryControl];

  return PlaybackState(
    controls: controls,
    systemActions: const {
      MediaAction.seek,
      MediaAction.skipToPrevious,
      MediaAction.skipToNext,
    },
    androidCompactActionIndices: hasCurrentSong ? const [0, 1, 2] : const [0],
    processingState: hasCurrentSong
        ? (processingState ?? AudioProcessingState.ready)
        : AudioProcessingState.idle,
    playing: isPlaying,
    updatePosition: position,
    bufferedPosition: duration,
    queueIndex: hasCurrentSong && queueIndex >= 0 ? queueIndex : null,
  );
}

MediaControl _favoriteControl(bool isCurrentSongLiked) {
  return MediaControl.custom(
    androidIcon: isCurrentSongLiked
        ? 'drawable/audio_service_favorite_filled'
        : 'drawable/audio_service_favorite_outline',
    label: isCurrentSongLiked ? '已喜欢' : '喜欢',
    name: playbackNotificationLikeAction,
  );
}

AudioProcessingState _mapProcessingState(
  just_audio.ProcessingState state, {
  required bool hasCurrentSong,
}) {
  if (!hasCurrentSong) return AudioProcessingState.idle;
  return switch (state) {
    just_audio.ProcessingState.idle => AudioProcessingState.idle,
    just_audio.ProcessingState.loading => AudioProcessingState.loading,
    just_audio.ProcessingState.buffering => AudioProcessingState.buffering,
    just_audio.ProcessingState.ready => AudioProcessingState.ready,
    just_audio.ProcessingState.completed => AudioProcessingState.completed,
  };
}

MediaItem createPlaybackMediaItem(
  Song song, {
  String? sourceUrl,
  Duration? duration,
}) {
  final artist = song.artistNames.trim();
  final artUri = _parseOptionalUri(song.coverUrl ?? song.album?.coverUrl);
  final effectiveDuration = duration != null && duration > Duration.zero
      ? duration
      : song.duration;
  final extras = <String, dynamic>{
    'platform': song.platform.name,
    'songId': song.id,
  };
  if (sourceUrl != null) {
    extras['sourceUrl'] = sourceUrl;
  }
  return MediaItem(
    id: '${song.platform.name}:${song.id}',
    title: song.name,
    album: song.album?.name,
    artist: artist.isEmpty ? null : artist,
    duration: effectiveDuration == Duration.zero ? null : effectiveDuration,
    artUri: artUri,
    extras: extras,
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
