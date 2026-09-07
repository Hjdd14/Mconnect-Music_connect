import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' show AudioPlayer, ProcessingState;
import '../../../../core/diagnostics/diagnostics_service.dart';
import '../../../../core/platform/platform_utils.dart';
import '../../../audio_effects/presentation/providers/audio_effects_provider.dart';
import '../../../../models/audio_quality.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';
import '../../../../platform/base/platform_registry.dart';
import '../../../../platform/base/music_platform.dart';
import '../../../library/presentation/providers/likes_provider.dart';
import '../../data/media_kit_windows_audio_controller.dart';
import '../../data/player_audio_controller.dart';
import '../../data/player_playback_memory_store.dart';
import '../../data/playback_keep_alive_service.dart';
import '../../data/playback_notification_service.dart' as playback_notification;

export '../../data/player_audio_controller.dart';

enum RepeatMode { off, all, one }

typedef SongLikeResolver = bool Function(Song song);
typedef SongLikeToggle = Future<void> Function(Song song);

@visibleForTesting
PlayerAudioController defaultPlayerAudioControllerFactory() {
  if (PlatformUtils.isAndroid) {
    return playback_notification.AudioServicePlayerController.instance;
  }
  if (PlatformUtils.isWindows) {
    return MediaKitWindowsAudioController();
  }
  return JustAudioController();
}

playback_notification.PlaybackNotificationController
defaultPlaybackNotificationController() {
  return PlatformUtils.isAndroid
      ? playback_notification.AudioServicePlayerController.instance
      : const playback_notification.NoopPlaybackNotificationController();
}

@visibleForTesting
String localSongPlaybackUrlForTest(String id) => _localSongPlaybackUrl(id);

String _localSongPlaybackUrl(String id) {
  final uri = Uri.tryParse(id);
  if (uri != null && (uri.scheme == 'content' || uri.scheme == 'file')) {
    return id;
  }
  return Uri.file(id).toString();
}

class PlayerState {
  final Song? currentSong;
  final List<Song> playlist;
  final int currentIndex;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final AudioLevel currentQuality;
  final AudioQualityPreference qualityPreference;
  final String? error;
  final bool isShuffle;
  final RepeatMode repeatMode;
  final bool isTransitioning;

  const PlayerState({
    this.currentSong,
    this.playlist = const [],
    this.currentIndex = -1,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.currentQuality = AudioLevel.low,
    this.qualityPreference = AudioQualityPreference.fixed,
    this.error,
    this.isShuffle = false,
    this.repeatMode = RepeatMode.off,
    this.isTransitioning = false,
  });

  PlayerState copyWith({
    Song? currentSong,
    List<Song>? playlist,
    int? currentIndex,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    AudioLevel? currentQuality,
    AudioQualityPreference? qualityPreference,
    String? Function()? error,
    bool? isShuffle,
    RepeatMode? repeatMode,
    bool? isTransitioning,
  }) {
    return PlayerState(
      currentSong: currentSong ?? this.currentSong,
      playlist: playlist ?? this.playlist,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      currentQuality: currentQuality ?? this.currentQuality,
      qualityPreference: qualityPreference ?? this.qualityPreference,
      error: error != null ? error() : this.error,
      isShuffle: isShuffle ?? this.isShuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      isTransitioning: isTransitioning ?? this.isTransitioning,
    );
  }
}

/// Simple async mutex to serialize audio operations and prevent platform channel deadlocks.
class _AudioMutex {
  Future<void>? _last;

  Future<T> run<T>(Future<T> Function() fn, {String label = 'audio'}) async {
    final prev = _last;
    final completer = Completer<void>();
    _last = completer.future;
    final wait = Stopwatch()..start();
    try {
      if (prev != null) await prev;
      if (kDebugMode && wait.elapsedMilliseconds > 100) {
        debugPrint('AudioMutex[$label] waited ${wait.elapsedMilliseconds}ms');
      }
      if (wait.elapsedMilliseconds > 500) {
        DiagnosticsService.instance.record(
          'slow_operation',
          'audio_mutex_wait',
          data: {'label': label, 'elapsed_ms': wait.elapsedMilliseconds},
        );
      }
      return await fn();
    } finally {
      completer.complete();
    }
  }
}

class PlayerNotifier extends StateNotifier<PlayerState> {
  static const _playbackPositionAdvanceTolerance = Duration(seconds: 1);
  static const _playbackEndTolerance = Duration(seconds: 5);
  static const _maxPlaybackRecoveryAttemptsPerSong = 2;

  PlayerAudioController? _audioController;
  final MusicPlatform Function(PlatformType) _platformResolver;
  final PlayerAudioController Function() _audioControllerFactory;
  final Duration _audioOperationTimeout;
  final Duration _audioDisposeTimeout;
  final Duration _qualitySwitchTimeout;
  final Duration _playbackMemorySaveInterval;
  final Duration _playbackHealthCheckInterval;
  final Duration _playbackStallThreshold;
  final Duration _playbackRecoveryCooldown;
  final Duration _playbackStartupGracePeriod;
  final DateTime Function() _now;
  final PlayerPlaybackMemoryStore _playbackMemoryStore;
  final playback_notification.PlaybackNotificationController
  _notificationController;
  final PlaybackKeepAliveController _keepAliveController;
  final SongLikeResolver _isSongLiked;
  final SongLikeToggle? _toggleSongLike;
  final List<StreamSubscription> _subscriptions = [];
  final _mutex = _AudioMutex();
  bool _isSwitchingQuality = false;
  bool _restoredSourceNeedsLoad = false;
  int _lastPositionSecond = -1;
  int _playRequestId = 0;
  int _qualityRequestId = 0;
  Timer? _transitionWatchdog;
  Timer? _playbackMemoryTimer;
  Timer? _playbackHealthTimer;
  PlayerPlaybackMemory? _pendingPlaybackMemory;
  bool _fadeEnabled = false;
  Duration _fadeDuration = const Duration(milliseconds: 800);
  bool _lastKeepAlivePlaying = false;
  int _fadeGeneration = 0;
  ProcessingState _lastProcessingState = ProcessingState.idle;
  DateTime? _lastProcessingStateChangedAt;
  Duration _lastPlaybackHealthPosition = Duration.zero;
  DateTime? _lastPlaybackHealthPositionChangedAt;
  DateTime? _playbackHealthGraceUntil;
  DateTime? _lastPlaybackRecoveryAt;
  bool _isRecoveringPlayback = false;
  String? _healthSongKey;
  int _healthPlayRequestId = 0;
  int _healthQualityRequestId = 0;
  String? _recoverySongKey;
  int _recoveryAttemptsForSong = 0;
  String? _recoveryLimitReportedSongKey;

  PlayerNotifier({
    PlayerAudioController? audioController,
    MusicPlatform Function(PlatformType)? platformResolver,
    PlayerAudioController Function()? audioControllerFactory,
    Duration audioOperationTimeout = const Duration(seconds: 10),
    Duration audioDisposeTimeout = const Duration(seconds: 3),
    Duration? qualitySwitchTimeout,
    PlayerPlaybackMemoryStore playbackMemoryStore =
        const NoopPlayerPlaybackMemoryStore(),
    Duration playbackMemorySaveInterval = const Duration(seconds: 5),
    playback_notification.PlaybackNotificationController?
    notificationController,
    PlaybackKeepAliveController? keepAliveController,
    SongLikeResolver? isSongLiked,
    SongLikeToggle? toggleSongLike,
    Duration playbackHealthCheckInterval = const Duration(seconds: 5),
    Duration playbackStallThreshold = const Duration(seconds: 12),
    Duration playbackRecoveryCooldown = const Duration(seconds: 30),
    Duration playbackStartupGracePeriod = const Duration(seconds: 8),
    DateTime Function()? now,
  }) : _audioController = audioController,
       _platformResolver = platformResolver ?? PlatformRegistry.get,
       _audioControllerFactory =
           audioControllerFactory ?? defaultPlayerAudioControllerFactory,
       _audioOperationTimeout = audioOperationTimeout,
       _audioDisposeTimeout = audioDisposeTimeout,
       _qualitySwitchTimeout = qualitySwitchTimeout ?? audioOperationTimeout,
       _playbackHealthCheckInterval = playbackHealthCheckInterval,
       _playbackStallThreshold = playbackStallThreshold,
       _playbackRecoveryCooldown = playbackRecoveryCooldown,
       _playbackStartupGracePeriod = playbackStartupGracePeriod,
       _now = now ?? DateTime.now,
       _playbackMemoryStore = playbackMemoryStore,
       _playbackMemorySaveInterval = playbackMemorySaveInterval,
       _notificationController =
           notificationController ?? defaultPlaybackNotificationController(),
       _keepAliveController =
           keepAliveController ??
           MethodChannelPlaybackKeepAliveController.instance,
       _isSongLiked = isSongLiked ?? ((_) => false),
       _toggleSongLike = toggleSongLike,
       super(const PlayerState()) {
    _notificationController.attach(
      playback_notification.PlaybackNotificationActions(
        play: _playFromNotification,
        pause: pause,
        skipToNext: skipToNext,
        skipToPrevious: skipToPrevious,
        seek: seek,
        toggleLikeCurrentSong: _toggleLikeCurrentSongFromNotification,
      ),
    );
    if (audioController != null) {
      _setupListeners(audioController);
    }
    unawaited(_restorePlaybackMemory());
    _syncNotificationState();
    _startPlaybackHealthMonitor();
  }

  Future<void> _playFromNotification() async {
    if (_restoredSourceNeedsLoad && state.currentSong != null) {
      await _playRestoredSong();
      return;
    }
    await togglePlay();
  }

  Future<void> _toggleLikeCurrentSongFromNotification() async {
    final song = state.currentSong;
    final toggle = _toggleSongLike;
    if (song == null || toggle == null) return;
    await toggle(song);
    _syncNotificationState();
  }

  PlayerAudioController _ensureAudioController() {
    final existing = _audioController;
    if (existing != null) return existing;
    final controller = _audioControllerFactory();
    _audioController = controller;
    _setupListeners(controller);
    return controller;
  }

  void _setState(PlayerState nextState) {
    state = nextState;
    _syncNotificationState();
    unawaited(_syncPlaybackKeepAlive(nextState.isPlaying));
  }

  void _syncNotificationState() {
    _notificationController.update(
      currentSong: state.currentSong,
      playlist: state.playlist,
      currentIndex: state.currentIndex,
      isCurrentSongLiked:
          state.currentSong != null && _isSongLiked(state.currentSong!),
      isPlaying: state.isPlaying,
      position: state.position,
      duration: state.duration,
    );
  }

  Duration _initialDurationForSong(Song song) {
    if (song.duration > Duration.zero) return song.duration;
    if (PlatformUtils.isAndroid && state.duration > Duration.zero) {
      return state.duration;
    }
    return Duration.zero;
  }

  Duration? _durationFromController(Duration? duration) {
    final isEmptyDuration = duration == null || duration == Duration.zero;
    if (PlatformUtils.isAndroid &&
        state.isTransitioning &&
        isEmptyDuration &&
        state.duration > Duration.zero) {
      return null;
    }
    return duration ?? Duration.zero;
  }

  bool _shouldKeepPlayingThroughTransientState(AudioPlaybackState playerState) {
    return PlatformUtils.isAndroid &&
        state.isTransitioning &&
        state.isPlaying &&
        !playerState.playing;
  }

  void refreshNotificationState() {
    _syncNotificationState();
  }

  Future<void> _syncPlaybackKeepAlive(
    bool isPlaying, {
    bool force = false,
  }) async {
    if (!force && _lastKeepAlivePlaying == isPlaying) return;
    _lastKeepAlivePlaying = isPlaying;
    await _keepAliveController.setPlaying(isPlaying, force: force);
  }

  Future<void> reassertBackgroundPlayback() async {
    _syncNotificationState();
    DiagnosticsService.instance.record(
      'background_playback',
      'reassert',
      data: {
        'is_playing': state.isPlaying,
        'position_ms': state.position.inMilliseconds,
        'duration_ms': state.duration.inMilliseconds,
        'song_id': state.currentSong?.id,
        'platform': state.currentSong?.platform.name,
      },
    );
    if (!state.isPlaying) return;
    await _syncPlaybackKeepAlive(true, force: true);
  }

  void _startPlaybackHealthMonitor() {
    if (!PlatformUtils.isAndroid) return;
    if (_playbackHealthCheckInterval <= Duration.zero) return;
    _playbackHealthTimer = Timer.periodic(
      _playbackHealthCheckInterval,
      (_) => unawaited(_checkPlaybackHealth()),
    );
  }

  @visibleForTesting
  Future<void> runPlaybackHealthCheckForTest() => _checkPlaybackHealth();

  String? _songKey(Song? song) =>
      song == null ? null : '${song.platform.name}:${song.id}';

  bool _isOnlineSong(Song song) => song.platform != PlatformType.local;

  bool _isNearPlaybackEnd() {
    final song = state.currentSong;
    if (song == null) return true;
    final effectiveDuration = state.duration == Duration.zero
        ? song.duration
        : state.duration;
    if (effectiveDuration == Duration.zero) return false;
    return state.position + _playbackEndTolerance >= effectiveDuration;
  }

  bool _isStalledProcessingState(ProcessingState state) {
    return state == ProcessingState.idle ||
        state == ProcessingState.loading ||
        state == ProcessingState.buffering;
  }

  bool _samePlaybackHealthFingerprint() {
    return _healthSongKey == _songKey(state.currentSong) &&
        _healthPlayRequestId == _playRequestId &&
        _healthQualityRequestId == _qualityRequestId;
  }

  void _resetPlaybackRecoveryIfSongChanged(String? songKey) {
    if (_recoverySongKey == songKey) return;
    _recoverySongKey = songKey;
    _recoveryAttemptsForSong = 0;
    _recoveryLimitReportedSongKey = null;
  }

  void _resetPlaybackHealthWindow({
    bool applyGrace = true,
    bool resetRecoveryAttempts = false,
  }) {
    final now = _now();
    final songKey = _songKey(state.currentSong);
    _healthSongKey = songKey;
    _healthPlayRequestId = _playRequestId;
    _healthQualityRequestId = _qualityRequestId;
    _lastPlaybackHealthPosition = state.position;
    _lastPlaybackHealthPositionChangedAt = now;
    _lastProcessingStateChangedAt = now;
    _playbackHealthGraceUntil =
        applyGrace && _playbackStartupGracePeriod > Duration.zero
        ? now.add(_playbackStartupGracePeriod)
        : null;
    if (resetRecoveryAttempts) {
      _recoverySongKey = songKey;
      _recoveryAttemptsForSong = 0;
      _recoveryLimitReportedSongKey = null;
    }
  }

  void _observePlaybackHealthPosition(Duration position) {
    if (position + _playbackPositionAdvanceTolerance <
        _lastPlaybackHealthPosition) {
      _lastPlaybackHealthPosition = position;
      _lastPlaybackHealthPositionChangedAt = _now();
      _healthSongKey = _songKey(state.currentSong);
      _healthPlayRequestId = _playRequestId;
      _healthQualityRequestId = _qualityRequestId;
      return;
    }
    if (position >=
        _lastPlaybackHealthPosition + _playbackPositionAdvanceTolerance) {
      _lastPlaybackHealthPosition = position;
      _lastPlaybackHealthPositionChangedAt = _now();
      _healthSongKey = _songKey(state.currentSong);
      _healthPlayRequestId = _playRequestId;
      _healthQualityRequestId = _qualityRequestId;
    }
  }

  bool _canCheckPlaybackHealth() {
    final song = state.currentSong;
    final controller = _audioController;
    return PlatformUtils.isAndroid &&
        song != null &&
        _isOnlineSong(song) &&
        state.isPlaying &&
        controller != null &&
        controller.playing &&
        !state.isTransitioning &&
        !_isSwitchingQuality &&
        !_restoredSourceNeedsLoad &&
        !_isRecoveringPlayback;
  }

  Future<void> _checkPlaybackHealth() async {
    if (!mounted) return;
    if (!_canCheckPlaybackHealth()) {
      _resetPlaybackHealthWindow(applyGrace: false);
      return;
    }
    final now = _now();
    final graceUntil = _playbackHealthGraceUntil;
    if (graceUntil != null && now.isBefore(graceUntil)) return;
    if (_isNearPlaybackEnd()) {
      _resetPlaybackHealthWindow(applyGrace: false);
      return;
    }
    if (!_samePlaybackHealthFingerprint()) {
      _resetPlaybackHealthWindow(applyGrace: false);
      return;
    }

    final processingChangedAt = _lastProcessingStateChangedAt;
    final processingStalled =
        _isStalledProcessingState(_lastProcessingState) &&
        processingChangedAt != null &&
        now.difference(processingChangedAt) >= _playbackStallThreshold;
    final positionChangedAt = _lastPlaybackHealthPositionChangedAt;
    final positionStalled =
        positionChangedAt != null &&
        now.difference(positionChangedAt) >= _playbackStallThreshold;
    if (!processingStalled && !positionStalled) return;

    final reason = processingStalled
        ? 'processing_${_lastProcessingState.name}'
        : 'position_stalled';
    await _recoverStalledOnlinePlayback(reason);
  }

  Future<void> _recoverStalledOnlinePlayback(String reason) async {
    if (_isRecoveringPlayback) return;
    final song = state.currentSong;
    if (song == null || !_isOnlineSong(song)) return;
    final songKey = _songKey(song);
    _resetPlaybackRecoveryIfSongChanged(songKey);

    final now = _now();
    final lastRecoveryAt = _lastPlaybackRecoveryAt;
    if (_playbackRecoveryCooldown > Duration.zero &&
        lastRecoveryAt != null &&
        now.difference(lastRecoveryAt) < _playbackRecoveryCooldown) {
      return;
    }
    if (_recoveryAttemptsForSong >= _maxPlaybackRecoveryAttemptsPerSong) {
      if (_recoveryLimitReportedSongKey != songKey) {
        _recoveryLimitReportedSongKey = songKey;
        DiagnosticsService.instance.record(
          'player',
          'playback_recovery_limit_reached',
          data: {
            'song_id': song.id,
            'platform': song.platform.name,
            'reason': reason,
            'attempts': _recoveryAttemptsForSong,
          },
        );
        _setState(
          state.copyWith(
            error: () => 'Playback stalled repeatedly. Please switch tracks.',
          ),
        );
      }
      return;
    }

    final requestId = _playRequestId;
    final qualityRequestId = _qualityRequestId;
    final quality = state.currentQuality;
    final resumePosition = state.position;
    _isRecoveringPlayback = true;
    _recoveryAttemptsForSong++;
    _lastPlaybackRecoveryAt = now;
    DiagnosticsService.instance.record(
      'player',
      'playback_stall_recovery_start',
      data: {
        'song_id': song.id,
        'platform': song.platform.name,
        'reason': reason,
        'position_ms': resumePosition.inMilliseconds,
        'attempt': _recoveryAttemptsForSong,
      },
    );

    try {
      final platform = _platformResolver(song.platform);
      final url = await DiagnosticsService.instance.measure(
        'platform.getSongUrl.stallRecovery',
        () => platform
            .getSongUrl(song.id, quality: quality)
            .timeout(const Duration(seconds: 10)),
        data: {
          'platform': song.platform.name,
          'song_id': song.id,
          'quality': quality.name,
        },
      );
      final stillSamePlayback =
          mounted &&
          requestId == _playRequestId &&
          qualityRequestId == _qualityRequestId &&
          state.currentSong?.id == song.id &&
          state.currentSong?.platform == song.platform;
      if (!stillSamePlayback) return;

      final fadeGeneration = _cancelActiveFades();
      await _safeStop();
      if (requestId != _playRequestId) return;
      await _setUrlWithRecovery(url, 'playbackStallRecovery');
      if (requestId != _playRequestId) return;
      if (resumePosition > Duration.zero) {
        await _safeSeek(resumePosition);
      }
      if (requestId != _playRequestId) return;
      await _safeSetVolume(1);
      _safePlay(requestId: requestId);
      _schedulePlaybackVolumeRecovery(fadeGeneration);
      _setState(
        state.copyWith(
          isPlaying: true,
          isTransitioning: false,
          position: resumePosition,
          error: () => null,
        ),
      );
      _resetPlaybackHealthWindow(applyGrace: true);
      DiagnosticsService.instance.record(
        'player',
        'playback_stall_recovery_success',
        data: {
          'song_id': song.id,
          'platform': song.platform.name,
          'position_ms': resumePosition.inMilliseconds,
          'attempt': _recoveryAttemptsForSong,
        },
      );
    } catch (error, stack) {
      if (!mounted) return;
      DiagnosticsService.instance.recordError(
        'player.playbackStallRecovery',
        error,
        stack,
        data: {
          'song_id': song.id,
          'platform': song.platform.name,
          'reason': reason,
          'attempt': _recoveryAttemptsForSong,
        },
      );
      _setState(
        state.copyWith(error: () => 'Playback recovery failed: $error'),
      );
    } finally {
      _isRecoveringPlayback = false;
    }
  }

  void _setupListeners(PlayerAudioController controller) {
    _subscriptions.add(
      controller.positionStream.listen((pos) {
        if (!mounted) return;
        if (!identical(controller, _audioController)) return;
        final sec = pos.inSeconds;
        if (sec != _lastPositionSecond) {
          _lastPositionSecond = sec;
          _setState(state.copyWith(position: pos));
          _observePlaybackHealthPosition(pos);
          _schedulePlaybackMemorySave();
        }
      }),
    );
    _subscriptions.add(
      controller.durationStream.listen((dur) {
        if (!mounted) return;
        if (!identical(controller, _audioController)) return;
        final duration = _durationFromController(dur);
        if (duration == null) return;
        _setState(state.copyWith(duration: duration));
        _schedulePlaybackMemorySave();
      }),
    );
    _subscriptions.add(
      controller.playerStateStream.listen(
        (playerState) {
          if (!mounted) return;
          if (!identical(controller, _audioController)) return;
          if (playerState.processingState != _lastProcessingState) {
            _lastProcessingState = playerState.processingState;
            _lastProcessingStateChangedAt = _now();
            _healthSongKey = _songKey(state.currentSong);
            _healthPlayRequestId = _playRequestId;
            _healthQualityRequestId = _qualityRequestId;
          }
          final clearTransition =
              state.isTransitioning &&
              !_shouldKeepPlayingThroughTransientState(playerState) &&
              (playerState.playing ||
                  playerState.processingState == ProcessingState.ready);
          final isPlaying = _shouldKeepPlayingThroughTransientState(playerState)
              ? true
              : playerState.playing;
          _setState(
            state.copyWith(
              isPlaying: isPlaying,
              isTransitioning: clearTransition ? false : state.isTransitioning,
            ),
          );
          _schedulePlaybackMemorySave();
          if (playerState.processingState == ProcessingState.completed) {
            if (!_shouldHandleCompletedEvent()) return;
            if (state.repeatMode == RepeatMode.one) {
              _safeSeek(Duration.zero);
              _safePlay();
            } else {
              skipToNext();
            }
          }
        },
        onError: (e) {
          debugPrint('PlayerState stream error: $e');
          if (!mounted) return;
          if (!identical(controller, _audioController)) return;
          _setState(
            state.copyWith(
              isPlaying: false,
              isTransitioning: false,
              error: () => 'Playback failed: $e',
            ),
          );
        },
      ),
    );
  }

  Future<void> _restorePlaybackMemory() async {
    try {
      final memory = await _playbackMemoryStore.load();
      if (!mounted || memory == null) return;
      final playlist = memory.playlist.isEmpty
          ? [memory.currentSong]
          : memory.playlist;
      var currentIndex = memory.currentIndex;
      if (currentIndex < 0 || currentIndex >= playlist.length) {
        currentIndex = playlist.indexWhere(
          (song) =>
              song.id == memory.currentSong.id &&
              song.platform == memory.currentSong.platform,
        );
      }
      if (currentIndex < 0) currentIndex = 0;
      _lastPositionSecond = memory.position.inSeconds;
      _restoredSourceNeedsLoad = true;
      _setState(
        state.copyWith(
          currentSong: memory.currentSong,
          playlist: playlist,
          currentIndex: currentIndex,
          isPlaying: false,
          position: memory.position,
          duration: memory.duration,
          currentQuality: memory.currentQuality,
          qualityPreference: memory.qualityPreference,
          error: () => null,
          isTransitioning: false,
        ),
      );
    } catch (e, s) {
      debugPrint('PlayerNotifier restore playback memory failed: $e');
      debugPrint('$s');
    }
  }

  PlayerPlaybackMemory? _buildPlaybackMemory() {
    final song = state.currentSong;
    if (song == null) return null;
    final playlist = state.playlist.isEmpty ? [song] : state.playlist;
    var currentIndex = state.currentIndex;
    if (currentIndex < 0 || currentIndex >= playlist.length) {
      currentIndex = playlist.indexWhere(
        (item) => item.id == song.id && item.platform == song.platform,
      );
    }
    return PlayerPlaybackMemory(
      currentSong: song,
      playlist: playlist,
      currentIndex: currentIndex < 0 ? 0 : currentIndex,
      position: state.position,
      duration: state.duration,
      currentQuality: state.currentQuality,
      qualityPreference: state.qualityPreference,
    );
  }

  void _schedulePlaybackMemorySave() {
    final memory = _buildPlaybackMemory();
    if (memory == null) return;
    _pendingPlaybackMemory = memory;
    if (_playbackMemorySaveInterval == Duration.zero) {
      unawaited(flushPlaybackMemory());
      return;
    }
    if (_playbackMemoryTimer?.isActive == true) return;
    _playbackMemoryTimer = Timer(
      _playbackMemorySaveInterval,
      () => unawaited(flushPlaybackMemory()),
    );
  }

  Future<void> flushPlaybackMemory() async {
    final memory = _pendingPlaybackMemory ?? _buildPlaybackMemory();
    if (memory == null) return;
    _pendingPlaybackMemory = null;
    _playbackMemoryTimer?.cancel();
    _playbackMemoryTimer = null;
    try {
      await _playbackMemoryStore.save(memory);
    } catch (e, s) {
      debugPrint('PlayerNotifier save playback memory failed: $e');
      debugPrint('$s');
    }
  }

  AudioPlayer get audioPlayer {
    final controller = _ensureAudioController();
    if (controller is JustAudioController) {
      return controller.player;
    }
    throw StateError(
      'The injected audio controller does not expose just_audio.AudioPlayer.',
    );
  }

  void setFadeOptions({required bool enabled, required Duration duration}) {
    _fadeEnabled = enabled;
    _fadeGeneration++;
    _fadeDuration = duration <= Duration.zero
        ? Duration.zero
        : Duration(milliseconds: duration.inMilliseconds.clamp(200, 3000));
    if (!enabled) {
      unawaited(_safeSetVolume(1));
    }
  }

  Future<void> applyEqualizerSettings(AudioEffectsSettings settings) async {
    try {
      await _ensureAudioController()
          .applyEqualizer(
            enabled: settings.equalizerEnabled,
            bandGains: settings.effectiveEqualizerBandGains,
          )
          .timeout(const Duration(milliseconds: 300));
    } catch (e, s) {
      debugPrint('PlayerNotifier applyEqualizer failed: $e');
      DiagnosticsService.instance.recordError(
        'player.equalizer',
        e,
        s,
        data: {'enabled': settings.equalizerEnabled},
      );
    }
  }

  Future<void> _safeSetVolume(double volume) async {
    try {
      await _ensureAudioController()
          .setVolume(volume.clamp(0.0, 1.0))
          .timeout(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint('PlayerNotifier setVolume failed: $e');
    }
  }

  Future<void> _runFade({
    required double from,
    required double to,
    required int generation,
  }) async {
    if (!_fadeEnabled) return;
    if (generation != _fadeGeneration) return;
    if (from == to) {
      await _safeSetVolume(to);
      return;
    }
    if (_fadeDuration == Duration.zero) {
      await _safeSetVolume(to);
      return;
    }
    const steps = 6;
    await _safeSetVolume(from);
    final stepDelay = Duration(
      milliseconds: max(1, _fadeDuration.inMilliseconds ~/ steps),
    );
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(stepDelay);
      if (generation != _fadeGeneration) return;
      final value = from + ((to - from) * i / steps);
      await _safeSetVolume(value);
    }
  }

  int _cancelActiveFades() => ++_fadeGeneration;

  bool _shouldHandleCompletedEvent() {
    if (state.isTransitioning || state.currentSong == null) {
      DiagnosticsService.instance.record(
        'player',
        'ignored_completed_event',
        data: {
          'reason': state.isTransitioning ? 'transitioning' : 'no_song',
          'song_id': state.currentSong?.id,
          'position_ms': state.position.inMilliseconds,
          'duration_ms': state.duration.inMilliseconds,
        },
      );
      return false;
    }

    final effectiveDuration = state.duration == Duration.zero
        ? state.currentSong!.duration
        : state.duration;
    const tolerance = Duration(seconds: 3);
    if (effectiveDuration > tolerance &&
        state.position + tolerance < effectiveDuration) {
      DiagnosticsService.instance.record(
        'player',
        'ignored_completed_event',
        data: {
          'reason': 'before_end',
          'song_id': state.currentSong?.id,
          'position_ms': state.position.inMilliseconds,
          'duration_ms': effectiveDuration.inMilliseconds,
        },
      );
      return false;
    }

    return true;
  }

  void _schedulePlaybackVolumeRecovery(int generation) {
    if (!_fadeEnabled) return;
    final delay = _fadeDuration + const Duration(milliseconds: 150);
    Timer(delay, () {
      if (!mounted || generation != _fadeGeneration || !state.isPlaying) {
        return;
      }
      unawaited(_safeSetVolume(1));
    });
  }

  /// Safely stop the player (ignores errors).
  Future<void> _safeStop() async {
    try {
      await DiagnosticsService.instance.measure(
        'player.stop',
        () => _ensureAudioController().stop().timeout(_audioOperationTimeout),
      );
    } catch (e) {
      debugPrint('PlayerNotifier stop failed, recreating player: $e');
      await _recreatePlayer();
    }
  }

  /// Start playback without awaiting the long-running just_audio play future.
  void _safePlay({int? requestId}) {
    try {
      unawaited(
        _ensureAudioController().play().catchError((Object e, StackTrace s) {
          _handleAsyncPlayError(e, s, requestId);
        }),
      );
    } catch (e, s) {
      _handleAsyncPlayError(e, s, requestId);
    }
  }

  Duration get _seekTimeout =>
      _audioOperationTimeout.compareTo(const Duration(seconds: 2)) <= 0
      ? _audioOperationTimeout
      : const Duration(seconds: 2);

  /// Safely seek (ignores errors).
  Future<void> _safeSeek(Duration position) async {
    try {
      await DiagnosticsService.instance.measure(
        'player.seek',
        () => _ensureAudioController().seek(position).timeout(_seekTimeout),
        data: {'position_ms': position.inMilliseconds},
      );
    } catch (e) {
      debugPrint('PlayerNotifier seek failed: $e');
      if (!mounted) return;
      if (e is TimeoutException || e is PlatformException) {
        unawaited(_recreatePlayer());
      }
    }
  }

  void _handleAsyncPlayError(Object error, StackTrace stack, int? requestId) {
    if (!mounted) return;
    if (requestId != null && requestId != _playRequestId) return;
    debugPrint('PlayerNotifier play error: $error');
    debugPrint('PlayerNotifier play stack: $stack');
    _setState(
      state.copyWith(
        isPlaying: false,
        isTransitioning: false,
        error: () => 'Playback failed: $error',
      ),
    );
    if (error is PlatformException || error is TimeoutException) {
      unawaited(_recreatePlayer());
    }
  }

  void _startTransitionWatchdog(int requestId) {
    _transitionWatchdog?.cancel();
    _transitionWatchdog = Timer(const Duration(seconds: 12), () {
      if (!mounted || requestId != _playRequestId || !state.isTransitioning) {
        return;
      }
      debugPrint(
        'PlayerNotifier: transition watchdog released request $requestId',
      );
      _setState(
        state.copyWith(
          isTransitioning: false,
          error: () => 'Playback is taking longer than expected.',
        ),
      );
    });
  }

  void _cancelTransitionWatchdog() {
    _transitionWatchdog?.cancel();
    _transitionWatchdog = null;
  }

  /// Recreate the AudioPlayer when the platform channel is corrupted.
  Future<void> _recreatePlayer() async {
    debugPrint('PlayerNotifier: recreating AudioPlayer');
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    try {
      await _audioController?.dispose().timeout(_audioDisposeTimeout);
    } catch (e) {
      debugPrint('PlayerNotifier dispose during recreate failed: $e');
    }
    _audioController = _audioControllerFactory();
    _setupListeners(_audioController!);
  }

  Future<void> _setUrlWithRecovery(String url, String label) async {
    try {
      await DiagnosticsService.instance.measure(
        'player.setUrl.$label',
        () => _ensureAudioController()
            .setUrl(url)
            .timeout(_audioOperationTimeout),
      );
    } catch (e) {
      debugPrint('$label: setUrl failed, recreating player: $e');
      await _recreatePlayer();
      await DiagnosticsService.instance.measure(
        'player.setUrl.$label.retry',
        () => _ensureAudioController()
            .setUrl(url)
            .timeout(_audioOperationTimeout),
      );
    }
  }

  Future<AudioLevel> _resolvePlaybackQuality(
    Song song,
    MusicPlatform? platform,
  ) async {
    if (song.platform == PlatformType.local || platform == null) {
      return state.currentQuality;
    }
    if (state.qualityPreference != AudioQualityPreference.highest) {
      return state.currentQuality;
    }

    final qualities = song.availableQualities.isNotEmpty
        ? song.availableQualities
        : await DiagnosticsService.instance.measure(
            'platform.getAvailableQualities.playback',
            () => platform
                .getAvailableQualities(song.id)
                .timeout(const Duration(seconds: 8)),
            data: {'platform': song.platform.name, 'song_id': song.id},
          );
    if (qualities.isEmpty) return state.currentQuality;
    return _highestQualityLevel(qualities);
  }

  AudioLevel _highestQualityLevel(List<AudioQuality> qualities) {
    return qualities
        .map((quality) => quality.level)
        .reduce((a, b) => a.index >= b.index ? a : b);
  }

  Future<void> playSong(Song song) async {
    _qualityRequestId++;
    return _mutex.run(() async {
      final requestId = ++_playRequestId;
      DiagnosticsService.instance.record(
        'player',
        'play_song_start',
        data: {
          'song_id': song.id,
          'platform': song.platform.name,
          'name': song.name,
        },
      );
      _startTransitionWatchdog(requestId);
      final platform = song.platform == PlatformType.local
          ? null
          : _platformResolver(song.platform);
      debugPrint(
        'playSong: ${song.name} (${song.platform.name}, id=${song.id})',
      );
      try {
        _restoredSourceNeedsLoad = false;
        final fadeGeneration = _cancelActiveFades();
        // Update UI immediately
        final newIndex = state.playlist.indexWhere(
          (s) => s.id == song.id && s.platform == song.platform,
        );
        final newPlaylist = List<Song>.from(state.playlist);
        final initialDuration = _initialDurationForSong(song);
        final transitionPlayingIntent = PlatformUtils.isAndroid
            ? true
            : state.isPlaying;
        if (newIndex == -1) {
          newPlaylist.add(song);
          _setState(
            state.copyWith(
              currentSong: song,
              playlist: newPlaylist,
              currentIndex: newPlaylist.length - 1,
              isPlaying: transitionPlayingIntent,
              position: Duration.zero,
              duration: initialDuration,
              error: () => null,
              isTransitioning: true,
            ),
          );
        } else {
          _setState(
            state.copyWith(
              currentSong: song,
              currentIndex: newIndex,
              isPlaying: transitionPlayingIntent,
              position: Duration.zero,
              duration: initialDuration,
              error: () => null,
              isTransitioning: true,
            ),
          );
        }
        _resetPlaybackHealthWindow(resetRecoveryAttempts: true);
        _schedulePlaybackMemorySave();

        final playbackQuality = await _resolvePlaybackQuality(song, platform);
        if (requestId != _playRequestId) return;
        if (playbackQuality != state.currentQuality) {
          _setState(state.copyWith(currentQuality: playbackQuality));
        }
        final url = song.platform == PlatformType.local
            ? _localSongPlaybackUrl(song.id)
            : await DiagnosticsService.instance.measure(
                'platform.getSongUrl',
                () => platform!
                    .getSongUrl(song.id, quality: playbackQuality)
                    .timeout(const Duration(seconds: 10)),
                data: {
                  'platform': song.platform.name,
                  'song_id': song.id,
                  'quality': playbackQuality.name,
                  'quality_preference': state.qualityPreference.name,
                },
              );
        final previewUrl = url.length > 80 ? '${url.substring(0, 80)}...' : url;
        debugPrint('playSong: got url=$previewUrl');
        if (requestId != _playRequestId) return;

        // CRITICAL: stop() before setUrl() to release the previous platform player
        await _safeStop();
        if (requestId != _playRequestId) return;

        await _setUrlWithRecovery(url, 'playSong');
        debugPrint('playSong: setUrl done');
        if (requestId != _playRequestId) return;

        if (_fadeEnabled) {
          await _runFade(from: 0, to: 0, generation: fadeGeneration);
        }
        _safePlay(requestId: requestId);
        unawaited(_runFade(from: 0, to: 1, generation: fadeGeneration));
        _schedulePlaybackVolumeRecovery(fadeGeneration);
        debugPrint('playSong: play() invoked');

        if (requestId == _playRequestId) {
          _setState(state.copyWith(isPlaying: true, isTransitioning: false));
          _resetPlaybackHealthWindow(applyGrace: true);
          _schedulePlaybackMemorySave();
          _cancelTransitionWatchdog();
          DiagnosticsService.instance.record(
            'player',
            'play_song_ready',
            data: {'song_id': song.id, 'platform': song.platform.name},
          );
        }
      } catch (e, s) {
        if (requestId != _playRequestId) return;
        debugPrint('Playback error: $e');
        debugPrint('Playback stack: $s');
        _cancelTransitionWatchdog();
        _setState(
          state.copyWith(
            isPlaying: false,
            isTransitioning: false,
            error: () => 'Playback failed: ${e.toString()}',
          ),
        );
        DiagnosticsService.instance.recordError(
          'player.playSong',
          e,
          s,
          data: {'song_id': song.id, 'platform': song.platform.name},
        );
      }
    }, label: 'playSong');
  }

  Future<void> playPlaylist(List<Song> songs, {int startIndex = 0}) async {
    _setState(state.copyWith(playlist: songs, currentIndex: startIndex));
    _schedulePlaybackMemorySave();
    if (startIndex < songs.length) {
      await playSong(songs[startIndex]);
    }
  }

  Future<void> _playRestoredSong() async {
    final song = state.currentSong;
    if (song == null) return;
    final resumePosition = state.position;
    final quality = state.currentQuality;
    _qualityRequestId++;
    return _mutex.run(() async {
      final requestId = ++_playRequestId;
      _startTransitionWatchdog(requestId);
      final platform = song.platform == PlatformType.local
          ? null
          : _platformResolver(song.platform);
      try {
        final fadeGeneration = _cancelActiveFades();
        _setState(state.copyWith(isTransitioning: true, error: () => null));
        _resetPlaybackHealthWindow(resetRecoveryAttempts: true);
        final url = song.platform == PlatformType.local
            ? _localSongPlaybackUrl(song.id)
            : await DiagnosticsService.instance.measure(
                'platform.getSongUrl.restore',
                () => platform!
                    .getSongUrl(song.id, quality: quality)
                    .timeout(const Duration(seconds: 10)),
                data: {
                  'platform': song.platform.name,
                  'song_id': song.id,
                  'quality': quality.name,
                },
              );
        if (requestId != _playRequestId) return;

        await _safeStop();
        if (requestId != _playRequestId) return;

        await _setUrlWithRecovery(url, 'restorePlaybackMemory');
        if (requestId != _playRequestId) return;

        if (resumePosition > Duration.zero) {
          await _safeSeek(resumePosition);
        }
        if (requestId != _playRequestId) return;

        _restoredSourceNeedsLoad = false;
        _safePlay(requestId: requestId);
        unawaited(_runFade(from: 0, to: 1, generation: fadeGeneration));
        _schedulePlaybackVolumeRecovery(fadeGeneration);
        _setState(
          state.copyWith(
            isPlaying: true,
            isTransitioning: false,
            position: resumePosition,
            error: () => null,
          ),
        );
        _resetPlaybackHealthWindow(applyGrace: true);
        _schedulePlaybackMemorySave();
        _cancelTransitionWatchdog();
      } catch (e, s) {
        if (requestId != _playRequestId) return;
        _cancelTransitionWatchdog();
        _setState(
          state.copyWith(
            isPlaying: false,
            isTransitioning: false,
            error: () => 'Playback failed: ${e.toString()}',
          ),
        );
        DiagnosticsService.instance.recordError(
          'player.restorePlaybackMemory',
          e,
          s,
          data: {'song_id': song.id, 'platform': song.platform.name},
        );
      }
    }, label: 'restorePlaybackMemory');
  }

  Future<void> togglePlay() async {
    if (_restoredSourceNeedsLoad && state.currentSong != null) {
      await _playRestoredSong();
      return;
    }
    return _mutex.run(() async {
      try {
        final audioController = _ensureAudioController();
        if (audioController.playing) {
          final fadeGeneration = _cancelActiveFades();
          await _runFade(from: 1, to: 0, generation: fadeGeneration);
          await audioController.pause().timeout(_audioOperationTimeout);
          _setState(state.copyWith(isPlaying: false));
          _resetPlaybackHealthWindow(applyGrace: false);
          if (_fadeEnabled) {
            await _safeSetVolume(1);
          }
        } else {
          final fadeGeneration = _cancelActiveFades();
          if (_fadeEnabled) {
            await _runFade(from: 0, to: 0, generation: fadeGeneration);
          }
          _safePlay();
          unawaited(_runFade(from: 0, to: 1, generation: fadeGeneration));
          _schedulePlaybackVolumeRecovery(fadeGeneration);
          _resetPlaybackHealthWindow(applyGrace: true);
        }
      } catch (e) {
        debugPrint('togglePlay: audio operation failed, recreating player: $e');
        await _recreatePlayer();
      }
    }, label: 'togglePlay');
  }

  Future<void> switchQuality(
    AudioLevel quality, {
    bool preferHighest = false,
  }) async {
    final requestId = ++_qualityRequestId;
    return _mutex.run(() async {
      final song = state.currentSong;
      final preference = preferHighest
          ? AudioQualityPreference.highest
          : AudioQualityPreference.fixed;
      if (song == null || _isSwitchingQuality) return;
      if (quality == state.currentQuality &&
          preference == state.qualityPreference) {
        return;
      }
      _isSwitchingQuality = true;
      _resetPlaybackHealthWindow(applyGrace: true);

      try {
        final platform = song.platform == PlatformType.local
            ? null
            : _platformResolver(song.platform);
        final controller = _ensureAudioController();
        final wasPlaying = controller.playing;
        final currentPosition = controller.position;
        final fadeGeneration = _cancelActiveFades();

        final url = song.platform == PlatformType.local
            ? _localSongPlaybackUrl(song.id)
            : await DiagnosticsService.instance.measure(
                'platform.getSongUrl.quality',
                () => platform!
                    .getSongUrl(song.id, quality: quality)
                    .timeout(_qualitySwitchTimeout),
                data: {
                  'platform': song.platform.name,
                  'song_id': song.id,
                  'quality': quality.name,
                  'quality_preference': preference.name,
                },
              );

        final stillSameSong =
            state.currentSong?.id == song.id &&
            state.currentSong?.platform == song.platform &&
            requestId == _qualityRequestId;
        if (!stillSameSong) return;

        await _safeStop();
        await _setUrlWithRecovery(url, 'switchQuality');
        await _safeSeek(currentPosition);

        if (requestId != _qualityRequestId) return;
        _setState(
          state.copyWith(
            currentQuality: quality,
            qualityPreference: preference,
            error: () => null,
          ),
        );
        _resetPlaybackHealthWindow(applyGrace: true);
        _schedulePlaybackMemorySave();

        if (wasPlaying) {
          _safePlay();
          unawaited(_runFade(from: 0, to: 1, generation: fadeGeneration));
          _schedulePlaybackVolumeRecovery(fadeGeneration);
        }
      } on TimeoutException {
        if (requestId == _qualityRequestId) {
          _setState(state.copyWith(error: () => 'Quality switch timed out.'));
        }
      } catch (e) {
        debugPrint('Quality switch error: $e');
        DiagnosticsService.instance.recordError(
          'player.switchQuality',
          e,
          StackTrace.current,
          data: {
            'song_id': song.id,
            'platform': song.platform.name,
            'quality': quality.name,
          },
        );
        if (requestId == _qualityRequestId) {
          _setState(
            state.copyWith(
              error: () => 'Quality switch failed: ${e.toString()}',
            ),
          );
        }
      } finally {
        if (requestId == _qualityRequestId) {
          _isSwitchingQuality = false;
        }
      }
    }, label: 'switchQuality');
  }

  void toggleShuffle() {
    final newShuffle = !state.isShuffle;
    if (newShuffle && state.playlist.length > 1) {
      final current = state.currentSong;
      final others = List<Song>.from(state.playlist)
        ..removeAt(state.currentIndex);
      others.shuffle();
      final newPlaylist = <Song>[?current, ...others];
      _setState(
        state.copyWith(isShuffle: true, playlist: newPlaylist, currentIndex: 0),
      );
    } else {
      _setState(state.copyWith(isShuffle: newShuffle));
    }
  }

  void cycleRepeatMode() {
    final modes = RepeatMode.values;
    final nextIndex = (state.repeatMode.index + 1) % modes.length;
    _setState(state.copyWith(repeatMode: modes[nextIndex]));
  }

  Future<void> skipToNext() async {
    if (state.playlist.isEmpty) return;

    if (state.repeatMode == RepeatMode.one) {
      return _mutex.run(() async {
        await _safeSeek(Duration.zero);
        _safePlay();
      }, label: 'skipToNext.repeatOne');
    }

    int nextIndex;
    if (state.isShuffle) {
      if (state.playlist.length == 1) {
        nextIndex = 0;
      } else {
        final rng = Random();
        do {
          nextIndex = rng.nextInt(state.playlist.length);
        } while (nextIndex == state.currentIndex);
      }
    } else {
      nextIndex = state.currentIndex + 1;
      if (nextIndex >= state.playlist.length) {
        if (state.repeatMode == RepeatMode.all) {
          nextIndex = 0;
        } else {
          return;
        }
      }
    }
    await playSong(state.playlist[nextIndex]);
  }

  Future<void> skipToPrevious() async {
    if (state.playlist.isEmpty) return;

    if (state.position.inSeconds > 3) {
      return _mutex.run(() async {
        await _safeSeek(Duration.zero);
      }, label: 'skipToPrevious.seekStart');
    }

    int prevIndex;
    if (state.isShuffle) {
      if (state.playlist.length == 1) {
        prevIndex = 0;
      } else {
        final rng = Random();
        do {
          prevIndex = rng.nextInt(state.playlist.length);
        } while (prevIndex == state.currentIndex);
      }
    } else {
      prevIndex = state.currentIndex - 1;
      if (prevIndex < 0) {
        if (state.repeatMode == RepeatMode.all) {
          prevIndex = state.playlist.length - 1;
        } else {
          prevIndex = 0;
        }
      }
    }
    await playSong(state.playlist[prevIndex]);
  }

  Future<void> seek(Duration position) async {
    if (!mounted) return;
    _setState(state.copyWith(position: position, isTransitioning: false));
    _resetPlaybackHealthWindow(applyGrace: true);
    _schedulePlaybackMemorySave();
    if (_restoredSourceNeedsLoad) return;
    await _safeSeek(position);
  }

  Future<void> pause() async {
    return _mutex.run(() async {
      try {
        final audioController = _ensureAudioController();
        if (!audioController.playing) return;
        final fadeGeneration = _cancelActiveFades();
        await _runFade(from: 1, to: 0, generation: fadeGeneration);
        await audioController.pause().timeout(_audioOperationTimeout);
        _setState(state.copyWith(isPlaying: false));
        _resetPlaybackHealthWindow(applyGrace: false);
        if (_fadeEnabled) {
          await _safeSetVolume(1);
        }
      } catch (e) {
        debugPrint('pause: audio operation failed, recreating player: $e');
        await _recreatePlayer();
      }
    }, label: 'pause');
  }

  void addToQueue(Song song) {
    final newPlaylist = List<Song>.from(state.playlist);
    final exists = newPlaylist.any(
      (s) => s.id == song.id && s.platform == song.platform,
    );
    if (!exists) {
      newPlaylist.add(song);
      _setState(state.copyWith(playlist: newPlaylist));
      _schedulePlaybackMemorySave();
    }
  }

  @override
  void dispose() {
    _cancelTransitionWatchdog();
    _playbackMemoryTimer?.cancel();
    _playbackHealthTimer?.cancel();
    unawaited(flushPlaybackMemory());
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _notificationController.detach();
    unawaited(_keepAliveController.dispose());
    _audioController?.dispose();
    super.dispose();
  }
}

final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>((
  ref,
) {
  final notifier = PlayerNotifier(
    playbackMemoryStore: HivePlayerPlaybackMemoryStore(),
    isSongLiked: (song) => ref
        .read(likesProvider)
        .songs
        .any((liked) => liked.id == song.id && liked.platform == song.platform),
    toggleSongLike: (song) =>
        ref.read(likesProvider.notifier).toggleLike(song).then((_) {}),
  );
  ref.listen<List<Song>>(
    likesProvider.select((state) => state.songs),
    (_, __) => notifier.refreshNotificationState(),
  );
  return notifier;
});
