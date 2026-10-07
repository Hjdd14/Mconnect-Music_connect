import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as just_audio;

import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/platform/platform_utils.dart';
import '../../../models/song.dart';
import 'audio_focus_diagnostics.dart';
import 'player_audio_controller.dart';

typedef PlaybackCommand = Future<void> Function();
typedef PlaybackSeekCommand = Future<void> Function(Duration position);

const playbackNotificationLikeAction = 'like_current_song';
const playbackNotificationLyricsAction = 'toggle_floating_lyrics';

class PlaybackNotificationActions {
  final PlaybackCommand play;
  final PlaybackCommand pause;
  final PlaybackCommand skipToNext;
  final PlaybackCommand skipToPrevious;
  final PlaybackSeekCommand seek;
  final PlaybackCommand toggleLikeCurrentSong;
  final PlaybackCommand toggleFloatingLyrics;

  const PlaybackNotificationActions({
    required this.play,
    required this.pause,
    required this.skipToNext,
    required this.skipToPrevious,
    required this.seek,
    required this.toggleLikeCurrentSong,
    required this.toggleFloatingLyrics,
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
    required bool isFloatingLyricsEnabled,
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
    required bool isFloatingLyricsEnabled,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) {}
}

class AudioServicePlayerController
    implements
        PlaybackNotificationController,
        PlayerAudioController,
        PlaybackSpeedCapable,
        SkipSilenceCapable {
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
  AudioFocusDiagnosticsObserver? _focusObserver;
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
      _focusObserver = AudioFocusDiagnosticsObserver(
        interruptionStream: session.interruptionEventStream,
        becomingNoisyStream: session.becomingNoisyEventStream,
      )..start();
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
    required bool isFloatingLyricsEnabled,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) {
    _handler.updatePlayback(
      currentSong: currentSong,
      playlist: playlist,
      currentIndex: currentIndex,
      isCurrentSongLiked: isCurrentSongLiked,
      isFloatingLyricsEnabled: isFloatingLyricsEnabled,
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
  double get volume => _ensureAudioController().volume;

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
    await _focusObserver?.dispose();
    _focusObserver = null;
    final controller = _audioController;
    _audioController = null;
    _handler.bindAudioController(null);
    await controller?.dispose();
  }

  @override
  double get playbackSpeed {
    final controller = _ensureAudioController();
    if (controller is! PlaybackSpeedCapable) return 1.0;
    return (controller as PlaybackSpeedCapable).playbackSpeed;
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    final controller = _ensureAudioController();
    if (controller is! PlaybackSpeedCapable) return;
    await (controller as PlaybackSpeedCapable).setPlaybackSpeed(speed);
  }

  @override
  Future<void> setSkipSilence(bool enabled) async {
    final controller = _ensureAudioController();
    if (controller is! SkipSilenceCapable) return;
    await (controller as SkipSilenceCapable).setSkipSilence(enabled);
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
  bool _isFloatingLyricsEnabled = false;
  just_audio.ProcessingState _processingState = just_audio.ProcessingState.idle;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _queueIndex = -1;

  // ── De-duplication state ─────────────────────────────────────────────────
  //
  // `updatePlayback` is called on **every** `_setState` — a `playSong` fires it
  // three or four times back to back, and position ticks keep firing it about
  // once a second forever. Every call used to rebuild and re-publish the whole
  // `MediaItem` queue and push a `mediaItem`, which made Android rebuild the
  // notification/MediaSession on the main thread; with a large playlist that is
  // an O(n) rebuild plus one audio_service channel message per tick, which is
  // what turned "tap next a few times" into an ANR.
  //
  // So the handler now publishes in two tiers:
  //
  // * **structural** (`queue.add` + `mediaItem.add`): only when the queue or the
  //   item actually changed — current song, queue contents/index, liked flag,
  //   floating-lyrics flag, or the media item's duration.
  // * **lightweight** (`playbackState.add`): position/duration progress. This is
  //   an in-process stream, and it is throttled below so a burst of updates in
  //   one frame produces one notification refresh instead of five.
  //
  // Deliberately *not* structural: play/pause. The play/pause button lives in
  // `playbackState.controls`, so that toggle is already covered by the broadcast
  // and must not rebuild the queue (it stays instant).

  /// Position deltas below this do not re-publish the playback state.
  ///
  /// `just_audio` reports a position roughly once a second, so in normal
  /// playback every tick still goes out (the progress bar stays smooth); the
  /// threshold only coalesces the bursts the provider produces within a frame.
  @visibleForTesting
  static const Duration positionBroadcastThreshold = Duration(seconds: 1);

  /// `null` until the first structural publish ever happened.
  List<Song>? _publishedPlaylist;
  Song? _publishedSong;
  int _publishedQueueIndex = -1;
  bool _publishedHasCurrentSong = false;
  bool _publishedLiked = false;
  bool _publishedLyrics = false;
  Duration _publishedItemDuration = Duration.zero;
  bool _hasPublishedStructure = false;

  bool _hasPublishedBroadcast = false;
  bool _publishedPlaying = false;
  Duration _publishedPosition = Duration.zero;
  Duration _publishedDuration = Duration.zero;

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
    required bool isFloatingLyricsEnabled,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) {
    final song = currentSong;
    _hasCurrentSong = song != null;
    _isFloatingLyricsEnabled = isFloatingLyricsEnabled;
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

    final firstPublish = !_hasPublishedStructure;
    final songChanged = !_sameSongOrNull(song, _publishedSong);
    final hasSongChanged = _hasCurrentSong != _publishedHasCurrentSong;
    final playlistChanged = !_playlistMatches(
      effectivePlaylist,
      _publishedPlaylist,
    );
    final queueIndexChanged = effectiveIndex != _publishedQueueIndex;
    final controlsChanged =
        _isCurrentSongLiked != _publishedLiked ||
        _isFloatingLyricsEnabled != _publishedLyrics;
    final itemDuration = _effectiveItemDuration(song);
    final itemDurationChanged = itemDuration != _publishedItemDuration;

    // Anything that changes the queue, the item or the notification controls.
    // Play/pause is intentionally absent: it only lives in `playbackState`
    // (see [_shouldBroadcast]), so toggling it must never rebuild the queue.
    final structural =
        firstPublish ||
        songChanged ||
        hasSongChanged ||
        playlistChanged ||
        queueIndexChanged ||
        controlsChanged;

    if (structural) {
      queue.add(buildPlaybackNotificationQueue(effectivePlaylist));
      mediaItem.add(
        song == null ? null : createPlaybackMediaItem(song, duration: _duration),
      );
      _publishedPlaylist = effectivePlaylist;
      _publishedSong = song;
      _publishedQueueIndex = effectiveIndex;
      _publishedHasCurrentSong = _hasCurrentSong;
      _publishedLiked = _isCurrentSongLiked;
      _publishedLyrics = _isFloatingLyricsEnabled;
      _publishedItemDuration = itemDuration;
      _hasPublishedStructure = true;
    } else if (itemDurationChanged) {
      // The duration the notification shows only arrived after the item was
      // published (just_audio reports it asynchronously). Refresh the item and
      // nothing else — a duration tick must not rebuild the queue.
      mediaItem.add(
        song == null ? null : createPlaybackMediaItem(song, duration: _duration),
      );
      _publishedItemDuration = itemDuration;
    }

    if (_shouldBroadcast(structural: structural)) {
      _broadcastPlaybackState();
    }
  }

  /// The duration the published [MediaItem] carries (see
  /// [createPlaybackMediaItem]: the controller's duration wins when known).
  Duration _effectiveItemDuration(Song? song) {
    if (song == null) return Duration.zero;
    return _duration > Duration.zero ? _duration : song.duration;
  }

  /// Cheap-enough queue comparison.
  ///
  /// Discriminators, and why they are enough:
  /// * **list identity** — `player_provider` passes the *same* immutable
  ///   `state.playlist` instance for position-only updates, so the common case
  ///   short-circuits on `identical`;
  /// * **length** — covers append/remove/clear;
  /// * **first** and **last** song — covers reordering and "another queue was
  ///   loaded", which never keep both ends while changing the middle.
  ///
  /// A full element-wise comparison is avoided on purpose: it would run on every
  /// update (once a second, forever), i.e. exactly the O(n)-per-tick cost this
  /// change exists to delete. The trade-off is that replacing a middle element
  /// while keeping length/first/last is not detected — the app's own queue
  /// mutations (add/remove/clear/reorder/play-a-song) all move one of the
  /// discriminators, so that case does not occur in practice.
  static bool _playlistMatches(List<Song> next, List<Song>? previous) {
    if (previous == null) return false;
    if (identical(next, previous)) return true;
    if (next.length != previous.length) return false;
    if (next.isEmpty) return true;
    return _sameSong(next.first, previous.first) &&
        _sameSong(next.last, previous.last);
  }

  /// Whether the published playback state has to be emitted again.
  ///
  /// A structural change, a first-ever publish and a play/pause change always
  /// go out (test ③: the toggle must be instant). Otherwise only a real
  /// position/duration move does, and a position move smaller than
  /// [positionBroadcastThreshold] is coalesced. A backwards move is a seek and
  /// is published immediately, or the notification progress would run backwards
  /// after the user drags.
  bool _shouldBroadcast({required bool structural}) {
    if (structural || !_hasPublishedBroadcast) return true;
    if (_playing != _publishedPlaying) return true;
    if (_duration != _publishedDuration) return true;
    if (_position == _publishedPosition) return false;
    if (_position < _publishedPosition) return true;
    return _position - _publishedPosition >= positionBroadcastThreshold;
  }

  void _broadcastPlaybackState() {
    _hasPublishedBroadcast = true;
    _publishedPlaying = _playing;
    _publishedPosition = _position;
    _publishedDuration = _duration;
    playbackState.add(
      buildPlaybackNotificationState(
        hasCurrentSong: _hasCurrentSong,
        isPlaying: _playing,
        isCurrentSongLiked: _isCurrentSongLiked,
        isFloatingLyricsEnabled: _isFloatingLyricsEnabled,
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
    if (name == playbackNotificationLyricsAction) {
      await _actions?.toggleFloatingLyrics();
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
  required bool isFloatingLyricsEnabled,
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
          _lyricsControl(isFloatingLyricsEnabled),
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

/// Fourth action on the media notification: toggles the floating lyrics
/// overlay. Required because a locked overlay cannot be closed from the
/// overlay itself, so the notification shade is the second exit.
MediaControl _lyricsControl(bool isFloatingLyricsEnabled) {
  return MediaControl.custom(
    androidIcon: isFloatingLyricsEnabled
        ? 'drawable/audio_service_lyrics_on'
        : 'drawable/audio_service_lyrics_off',
    label: isFloatingLyricsEnabled ? '关闭歌词' : '歌词',
    name: playbackNotificationLyricsAction,
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

/// [Song] identity comparison that also handles "no current song".
bool _sameSongOrNull(Song? a, Song? b) {
  if (a == null || b == null) return a == null && b == null;
  return _sameSong(a, b);
}

Uri? _parseOptionalUri(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return null;
  return uri;
}
