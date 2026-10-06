import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' show AudioPlayer, ProcessingState;
import '../../../../core/diagnostics/diagnostics_service.dart';
import '../../../../core/network/platform_http.dart';
import '../../../../core/platform/platform_utils.dart';
import '../../../audio_effects/presentation/providers/audio_effects_provider.dart';
import '../../../floating_lyrics/presentation/providers/floating_lyrics_provider.dart';
import '../../../../models/audio_quality.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';
import '../../../../platform/base/platform_registry.dart';
import '../../../../platform/base/music_platform.dart';
import '../../../library/presentation/providers/likes_provider.dart';
import '../../../download/presentation/providers/download_provider.dart';
import '../../../offline_cache/presentation/providers/offline_cache_provider.dart';
import '../../data/media_kit_windows_audio_controller.dart';
import '../../data/player_audio_controller.dart';
import '../../data/player_playback_memory_store.dart';
import '../../data/playback_keep_alive_service.dart';
import '../../data/playback_notification_service.dart' as playback_notification;

export '../../data/player_audio_controller.dart';

enum RepeatMode { off, all, one }

typedef SongLikeResolver = bool Function(Song song);
typedef SongLikeToggle = Future<void> Function(Song song);

/// Resolves the local file backing [song] when 离线模式 is on.
///
/// Backed by `DownloadNotifier.localFilePathFor`, which also stamps the file's
/// LRU access time. Injecting it keeps this notifier's tests independent of
/// Hive/Connectivity.
typedef OfflineFilePathResolver = Future<String?> Function(Song song);

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

  /// 播放倍速（1.0 = 原速）。仅当后端实现 [PlaybackSpeedCapable] 时可改。
  final double playbackSpeed;

  /// 是否跳过静音段（仅 Android/just_audio 后端支持）。
  final bool skipSilence;

  /// A-B 循环区间；两者都为非 null 时才生效。
  final Duration? abLoopStart;
  final Duration? abLoopEnd;

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
    this.playbackSpeed = 1.0,
    this.skipSilence = false,
    this.abLoopStart,
    this.abLoopEnd,
  });

  bool get hasAbLoop => abLoopStart != null && abLoopEnd != null;

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
    double? playbackSpeed,
    bool? skipSilence,
    Duration? Function()? abLoopStart,
    Duration? Function()? abLoopEnd,
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
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      skipSilence: skipSilence ?? this.skipSilence,
      abLoopStart: abLoopStart != null ? abLoopStart() : this.abLoopStart,
      abLoopEnd: abLoopEnd != null ? abLoopEnd() : this.abLoopEnd,
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
  final OfflineFilePathResolver? _offlineFilePathResolver;
  final bool Function() _isOfflineModeEnabled;
  final Future<void> Function()? _toggleFloatingLyrics;
  final bool Function() _isFloatingLyricsEnabled;
  final List<StreamSubscription> _subscriptions = [];
  final _mutex = _AudioMutex();
  final Random _random;
  /// 随机播放的"已播集合"（本轮尚未播过的曲目之外不再挑）。
  final Set<String> _shuffledPlayedSongKeys = {};
  /// 随机播放的历史栈，供 skipToPrevious 回到真正听过的那首。
  final List<int> _shuffleHistory = [];
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
  AudioEffectsSettings? _lastEqualizerSettings;
  bool _isSleepFadingOut = false;
  bool _isSeekingAbLoop = false;
  bool _lastKeepAlivePlaying = false;
  int _fadeGeneration = 0;
  ProcessingState _lastProcessingState = ProcessingState.idle;
  DateTime? _lastProcessingStateChangedAt;
  bool? _lastLoggedPlaying;
  ProcessingState _lastLoggedProcessingState = ProcessingState.idle;
  bool _hasLoggedPlayerState = false;
  DateTime? _lastVolumeWriteAt;
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
    this._audioDisposeTimeout = const Duration(seconds: 3),
    Duration? qualitySwitchTimeout,
    this._playbackMemoryStore = const NoopPlayerPlaybackMemoryStore(),
    this._playbackMemorySaveInterval = const Duration(seconds: 5),
    playback_notification.PlaybackNotificationController?
    notificationController,
    PlaybackKeepAliveController? keepAliveController,
    SongLikeResolver? isSongLiked,
    this._toggleSongLike,
    this._offlineFilePathResolver,
    bool Function()? isOfflineModeEnabled,
    this._toggleFloatingLyrics,
    bool Function()? isFloatingLyricsEnabled,
    this._playbackHealthCheckInterval = const Duration(seconds: 5),
    this._playbackStallThreshold = const Duration(seconds: 12),
    this._playbackRecoveryCooldown = const Duration(seconds: 30),
    this._playbackStartupGracePeriod = const Duration(seconds: 8),
    DateTime Function()? now,
    Random? random,
  }) : _audioController = audioController,
       _random = random ?? Random(),
       _platformResolver = platformResolver ?? PlatformRegistry.get,
       _audioControllerFactory =
           audioControllerFactory ?? defaultPlayerAudioControllerFactory,
       _audioOperationTimeout = audioOperationTimeout,
       _qualitySwitchTimeout = qualitySwitchTimeout ?? audioOperationTimeout,
       _now = now ?? DateTime.now,
       _notificationController =
           notificationController ?? defaultPlaybackNotificationController(),
       _keepAliveController =
           keepAliveController ??
           MethodChannelPlaybackKeepAliveController.instance,
       _isSongLiked = isSongLiked ?? ((_) => false),
       _isOfflineModeEnabled = isOfflineModeEnabled ?? (() => false),
       _isFloatingLyricsEnabled = isFloatingLyricsEnabled ?? (() => false),
       super(const PlayerState()) {
    _notificationController.attach(
      playback_notification.PlaybackNotificationActions(
        play: _playFromNotification,
        pause: pause,
        skipToNext: skipToNext,
        skipToPrevious: skipToPrevious,
        seek: seek,
        toggleLikeCurrentSong: _toggleLikeCurrentSongFromNotification,
        toggleFloatingLyrics: _toggleFloatingLyricsFromNotification,
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

  Future<void> _toggleFloatingLyricsFromNotification() async {
    final toggle = _toggleFloatingLyrics;
    if (toggle == null) return;
    await toggle();
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
      isFloatingLyricsEnabled: _isFloatingLyricsEnabled(),
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

  /// Whether a controller instance is still referenced. `dispose()` must leave
  /// this false so nothing can resurrect the disposed platform channel.
  @visibleForTesting
  bool get hasAudioControllerForTest => _audioController != null;

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
        !_isSleepFadingOut &&
        !_isRecoveringPlayback;
  }

  Future<void> _checkPlaybackHealth() async {
    if (!mounted) return;
    await _ensurePlaybackVolume();
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

  // 音量守护：健康监测 tick 里把残留在非 1.0 的播放器音量拉回满音量，
  // 避免淡入淡出被打断等泄漏让后台播放只走进度没有声音。
  Future<void> _ensurePlaybackVolume() async {
    if (!mounted) return;
    final controller = _audioController;
    if (controller == null) return;
    if (state.currentSong == null || !state.isPlaying) return;
    if (state.isTransitioning ||
        _isSwitchingQuality ||
        _isRecoveringPlayback ||
        _restoredSourceNeedsLoad) {
      return;
    }
    final current = controller.volume;
    if (current >= 1.0) return;
    if (_isSleepFadingOut) {
      // 睡眠定时的淡出是合法的非满音量窗口（它不依赖用户的淡入淡出开关）。
      return;
    }
    if (_fadeEnabled) {
      final lastWriteAt = _lastVolumeWriteAt;
      if (lastWriteAt != null &&
          _now().difference(lastWriteAt) <
              _fadeDuration + const Duration(seconds: 1)) {
        // 正在淡入淡出的合法非满音量窗口，不干预，避免顶掉淡入淡出。
        return;
      }
    }
    DiagnosticsService.instance.record(
      'player',
      'volume_watchdog_restore',
      data: {'volume': current, 'fade_enabled': _fadeEnabled},
    );
    await _safeSetVolume(1);
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

    // 自愈必须走 _AudioMutex：它做的是 stop/setUrl/seek/play 这一整套传输序列，
    // 以前被当作"内部恢复"豁免、裸奔执行，于是和持锁的 playSong 并发抢同一个
    // 控制器（可表现为点了 B 却在放 A）。锁自身不嵌套——内部没有任何
    // `_mutex.run`。
    try {
      await _mutex.run(() async {
        // 等锁期间播放可能已经换曲/换音质，重新确认后立即放弃。
        if (!mounted) return;
        if (requestId != _playRequestId || qualityRequestId != _qualityRequestId) {
          return;
        }
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
      }, label: 'stallRecovery');
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
        state.copyWith(error: () => '播放恢复失败：${_userFacingError(error)}'),
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
          _enforceAbLoop(pos);
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
          if (!_hasLoggedPlayerState ||
              _lastLoggedPlaying != playerState.playing ||
              _lastLoggedProcessingState != playerState.processingState) {
            _hasLoggedPlayerState = true;
            _lastLoggedPlaying = playerState.playing;
            _lastLoggedProcessingState = playerState.processingState;
            DiagnosticsService.instance.record(
              'player',
              'player_state',
              data: {
                'playing': playerState.playing,
                'processing_state': playerState.processingState.name,
              },
            );
          }
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
              error: () => _userFacingError(e),
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
    // Remembered so `_recreatePlayer` can push the same curve to the brand new
    // controller: a recreated player starts with the equalizer disabled.
    _lastEqualizerSettings = settings;
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

  /// Whether the current backend can change playback speed.
  bool get supportsPlaybackSpeed =>
      _ensureAudioController() is PlaybackSpeedCapable;

  /// Whether the current backend can skip silent passages.
  bool get supportsSkipSilence =>
      _ensureAudioController() is SkipSilenceCapable;

  /// Sets the playback speed, clamped to a sane range.
  ///
  /// Not routed through [_AudioMutex]: like the volume writes this is a single
  /// property write, not part of the stop/setUrl/seek/play transport sequence
  /// the mutex exists to serialize.
  Future<void> setPlaybackSpeed(double speed) async {
    final clamped = speed.clamp(0.5, 2.0).toDouble();
    final controller = _ensureAudioController();
    if (controller is! PlaybackSpeedCapable) {
      _setState(state.copyWith(error: () => '当前播放后端不支持倍速播放'));
      return;
    }
    // 显式转换：Dart 不会把 PlayerAudioController 提升为不相关的接口类型。
    final speedController = controller as PlaybackSpeedCapable;
    try {
      await speedController
          .setPlaybackSpeed(clamped)
          .timeout(_audioOperationTimeout);
      _setState(state.copyWith(playbackSpeed: clamped, error: () => null));
    } catch (e, s) {
      DiagnosticsService.instance.recordError(
        'player.setPlaybackSpeed',
        e,
        s,
        data: {'speed': clamped},
      );
      _setState(state.copyWith(error: () => '设置倍速失败：${_userFacingError(e)}'));
    }
  }

  Future<void> setSkipSilence(bool enabled) async {
    final controller = _ensureAudioController();
    if (controller is! SkipSilenceCapable) {
      _setState(state.copyWith(error: () => '当前播放后端不支持跳过静音'));
      return;
    }
    final skipSilenceController = controller as SkipSilenceCapable;
    try {
      await skipSilenceController
          .setSkipSilence(enabled)
          .timeout(_audioOperationTimeout);
      _setState(state.copyWith(skipSilence: enabled, error: () => null));
    } catch (e, s) {
      DiagnosticsService.instance.recordError(
        'player.setSkipSilence',
        e,
        s,
        data: {'enabled': enabled},
      );
      _setState(state.copyWith(error: () => '设置跳过静音失败：${_userFacingError(e)}'));
    }
  }

  /// Marks the start of an A-B loop at [position] (defaults to the current
  /// playback position).
  void setAbLoopStart([Duration? position]) {
    final start = position ?? state.position;
    final end = state.abLoopEnd;
    if (end != null && end <= start) {
      // 新的 A 落在 B 之后：丢弃已经无效的 B 而不是留下一个空区间。
      _setState(state.copyWith(abLoopStart: () => start, abLoopEnd: () => null));
      return;
    }
    _setState(state.copyWith(abLoopStart: () => start));
  }

  void setAbLoopEnd([Duration? position]) {
    final end = position ?? state.position;
    final start = state.abLoopStart;
    if (start == null || end <= start) {
      _setState(state.copyWith(error: () => 'B 点必须晚于 A 点'));
      return;
    }
    _setState(state.copyWith(abLoopEnd: () => end, error: () => null));
  }

  void clearAbLoop() {
    if (!state.hasAbLoop && state.abLoopStart == null) return;
    _setState(state.copyWith(abLoopStart: () => null, abLoopEnd: () => null));
  }

  void _enforceAbLoop(Duration position) {
    final start = state.abLoopStart;
    final end = state.abLoopEnd;
    if (start == null || end == null) return;
    if (position < end) return;
    if (_isSeekingAbLoop) return;
    _isSeekingAbLoop = true;
    unawaited(
      _safeSeek(start).whenComplete(() => _isSeekingAbLoop = false),
    );
  }

  Future<void> _safeSetVolume(double volume) async {
    final target = volume.clamp(0.0, 1.0);
    try {
      await _ensureAudioController()
          .setVolume(target)
          .timeout(const Duration(milliseconds: 300));
      _lastVolumeWriteAt = _now();
      DiagnosticsService.instance.record(
        'player',
        'volume_set',
        data: {'volume': target},
      );
    } catch (e, s) {
      debugPrint('PlayerNotifier setVolume failed: $e');
      DiagnosticsService.instance.recordError(
        'player.setVolume',
        e,
        s,
        data: {'volume': target},
      );
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

  /// Fades the current playback out and then pauses it.
  ///
  /// Used by the sleep timer: the previous implementation called `pause()`
  /// abruptly, cutting the audio mid-note. The ramp is written directly rather
  /// than reusing [_runFade] because that helper no-ops unless the user turned
  /// the regular fade-in/out setting on, and the sleep fade must always happen.
  Future<void> fadeOutAndPause({
    Duration duration = const Duration(milliseconds: 1500),
  }) async {
    return _mutex.run(() async {
      try {
        final controller = _ensureAudioController();
        if (!controller.playing) return;
        final generation = _cancelActiveFades();
        _isSleepFadingOut = true;
        await _rampVolume(
          from: controller.volume.clamp(0.0, 1.0),
          to: 0,
          duration: duration,
          generation: generation,
        );
        if (generation != _fadeGeneration) return;
        await controller.pause().timeout(_audioOperationTimeout);
        _setState(state.copyWith(isPlaying: false));
        _resetPlaybackHealthWindow(applyGrace: false);
        // 淡出到 0 后把播放器音量复位，否则下一次播放会静音。
        await _safeSetVolume(1);
      } catch (e, s) {
        debugPrint('fadeOutAndPause failed: $e');
        DiagnosticsService.instance.recordError('player.fadeOutAndPause', e, s);
        await _recreatePlayer();
      } finally {
        _isSleepFadingOut = false;
      }
    }, label: 'fadeOutAndPause');
  }

  Future<void> _rampVolume({
    required double from,
    required double to,
    required Duration duration,
    required int generation,
  }) async {
    if (generation != _fadeGeneration) return;
    if (from == to || duration <= Duration.zero) {
      await _safeSetVolume(to);
      return;
    }
    const steps = 6;
    final stepDelay = Duration(
      milliseconds: max(1, duration.inMilliseconds ~/ steps),
    );
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(stepDelay);
      if (generation != _fadeGeneration) return;
      await _safeSetVolume(from + ((to - from) * i / steps));
    }
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

  /// User-facing playback error text.
  ///
  /// Wave 1 unified the platform layer on typed [ApiException]s, so the player
  /// must surface `apiExceptionOf(e).message` (already localized) instead of
  /// concatenating `'Playback failed: $e'`, which was the source of the
  /// Chinese/English mixed strings in the UI.
  String _userFacingError(Object error) {
    if (error is TimeoutException) return '播放超时，请稍后重试';
    return apiExceptionOf(error).message;
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
        error: () => _userFacingError(error),
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
    await _restoreControllerAudioSettings();
  }

  /// Pushes the audio settings the fresh controller cannot know about.
  ///
  /// A recreated player starts with the equalizer disabled and its volume at
  /// the backend default; without this the user's EQ silently disappears and a
  /// non-full volume left over from an interrupted fade sticks, which is
  /// exactly the "progress moves but there is no sound" symptom the volume
  /// watchdog exists for.
  Future<void> _restoreControllerAudioSettings() async {
    final settings = _lastEqualizerSettings;
    if (settings != null) {
      await applyEqualizerSettings(settings);
    }
    final controller = _audioController;
    if (controller != null && controller is PlaybackSpeedCapable) {
      final speedController = controller as PlaybackSpeedCapable;
      if (state.playbackSpeed != 1.0) {
        try {
          await speedController
              .setPlaybackSpeed(state.playbackSpeed)
              .timeout(_audioOperationTimeout);
        } catch (e) {
          debugPrint('PlayerNotifier restore speed failed: $e');
        }
      }
    }
    if (controller != null && controller is SkipSilenceCapable) {
      final skipSilenceController = controller as SkipSilenceCapable;
      if (state.skipSilence) {
        try {
          await skipSilenceController
              .setSkipSilence(true)
              .timeout(_audioOperationTimeout);
        } catch (e) {
          debugPrint('PlayerNotifier restore skip silence failed: $e');
        }
      }
    }
    if (!_fadeEnabled) {
      await _safeSetVolume(1);
    }
  }

  /// Local file URI for [song] when 离线模式 is on, otherwise `null`.
  ///
  /// Returning `null` means "use the network"; the caller keeps its original
  /// streaming path. The resolver itself verifies the file still exists (see
  /// `DownloadNotifier.localFilePathFor`), and any failure here degrades to the
  /// network rather than blocking playback.
  Future<String?> _offlinePlaybackUrl(Song song) async {
    final resolver = _offlineFilePathResolver;
    if (resolver == null) return null;
    if (song.platform == PlatformType.local) return null;
    if (!_isOfflineModeEnabled()) return null;

    try {
      final path = await resolver(song);
      if (path == null || path.trim().isEmpty) return null;
      final url = _localSongPlaybackUrl(path);
      DiagnosticsService.instance.record(
        'player',
        'offline_playback_used',
        data: {
          'song_id': song.id,
          'platform': song.platform.name,
        },
      );
      return url;
    } catch (e, s) {
      DiagnosticsService.instance.recordError(
        'player.offlinePlayback',
        e,
        s,
        data: {'song_id': song.id, 'platform': song.platform.name},
      );
      return null;
    }
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
    return _mutex.run(() async {
      // 质量纪元必须在锁内推进。锁外推进正是 S-1 的死锁源：switchQuality 飞行中
      // 任意一次 playSong 都会把它的 requestId 推走，使 `finally` 里的复位条件
      // 不成立，`_isSwitchingQuality` 于是永为 true —— 换音质静默失效，并连带
      // 关闭健康监测（:457）与音量守护（:510），即"后台有进度没声音"的唯一自愈路径。
      _qualityRequestId++;
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
        // 换曲即失效：A-B 循环属于上一首的时间轴。
        if (state.abLoopStart != null || state.abLoopEnd != null) {
          _setState(
            state.copyWith(abLoopStart: () => null, abLoopEnd: () => null),
          );
        }
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

        // 离线模式优先：命中本地文件时既不需要质量探测，也不需要取流。
        final offlineUrl = await _offlinePlaybackUrl(song);
        if (requestId != _playRequestId) return;

        final String url;
        if (offlineUrl != null) {
          url = offlineUrl;
        } else {
          final playbackQuality = await _resolvePlaybackQuality(song, platform);
          if (requestId != _playRequestId) return;
          if (playbackQuality != state.currentQuality) {
            _setState(state.copyWith(currentQuality: playbackQuality));
          }
          url = song.platform == PlatformType.local
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
        }
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
            error: () => _userFacingError(e),
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
    _resetShuffleBookkeeping();
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
    return _mutex.run(() async {
      // 同 playSong：质量纪元只在锁内推进，避免把飞行中的换音质请求推走。
      _qualityRequestId++;
      final requestId = ++_playRequestId;
      _startTransitionWatchdog(requestId);
      final platform = song.platform == PlatformType.local
          ? null
          : _platformResolver(song.platform);
      try {
        final fadeGeneration = _cancelActiveFades();
        _setState(state.copyWith(isTransitioning: true, error: () => null));
        _resetPlaybackHealthWindow(resetRecoveryAttempts: true);
        final offlineUrl = await _offlinePlaybackUrl(song);
        if (requestId != _playRequestId) return;
        final String url;
        if (offlineUrl != null) {
          url = offlineUrl;
        } else if (song.platform == PlatformType.local) {
          url = _localSongPlaybackUrl(song.id);
        } else {
          url = await DiagnosticsService.instance.measure(
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
        }
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
            error: () => _userFacingError(e),
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
    return _mutex.run(() async {
      // 质量纪元在锁内推进（S-1）：锁外推进会让正在飞行的换音质请求看到
      // 「requestId != _qualityRequestId」而提前 return，其 finally 的复位条件
      // 随即不成立。
      final requestId = ++_qualityRequestId;
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
          _setState(state.copyWith(error: () => '换音质超时，请重试'));
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
              error: () => '换音质失败：${_userFacingError(e)}',
            ),
          );
        }
      } finally {
        // 无条件复位。以前这里是 `if (requestId == _qualityRequestId)`，
        // 一旦纪元被推走闸门就永远锁死：此后所有 switchQuality 都在上面
        // `if (_isSwitchingQuality) return;` 处直接返回（该 return 在 try
        // 之前，finally 不再执行），健康监测与音量守护也一起失效。
        _isSwitchingQuality = false;
      }
    }, label: 'switchQuality');
  }

  void toggleShuffle() {
    final newShuffle = !state.isShuffle;
    _resetShuffleBookkeeping();
    if (newShuffle && state.playlist.length > 1) {
      final current = state.currentSong;
      final others = List<Song>.from(state.playlist)
        ..removeAt(state.currentIndex);
      others.shuffle(_random);
      final newPlaylist = <Song>[?current, ...others];
      _setState(
        state.copyWith(isShuffle: true, playlist: newPlaylist, currentIndex: 0),
      );
    } else {
      _setState(state.copyWith(isShuffle: newShuffle));
    }
  }

  void _resetShuffleBookkeeping() {
    _shuffledPlayedSongKeys.clear();
    _shuffleHistory.clear();
  }

  /// Picks the next index for shuffle playback.
  ///
  /// Old implementation created a fresh `Random()` on every tick and only
  /// excluded `currentIndex`, so a long queue kept re-playing the same few
  /// tracks (sampling with replacement). This walks the queue without repeats,
  /// only starting a new round once every track has been played.
  int _pickShuffledIndex() {
    final playlist = state.playlist;
    final currentIndex = state.currentIndex;
    final currentKey = currentIndex >= 0 && currentIndex < playlist.length
        ? _songKey(playlist[currentIndex])
        : null;
    if (currentKey != null) {
      _shuffledPlayedSongKeys.add(currentKey);
    }

    var candidates = <int>[
      for (var i = 0; i < playlist.length; i++)
        if (i != currentIndex &&
            !_shuffledPlayedSongKeys.contains(_songKey(playlist[i])))
          i,
    ];
    if (candidates.isEmpty) {
      // 一整轮播完：重置已播集合，只排除当前曲。
      _shuffledPlayedSongKeys.clear();
      if (currentKey != null) {
        _shuffledPlayedSongKeys.add(currentKey);
      }
      candidates = [
        for (var i = 0; i < playlist.length; i++)
          if (i != currentIndex) i,
      ];
    }
    return candidates[_random.nextInt(candidates.length)];
  }

  void _pushShuffleHistory(int index) {
    final limit = state.playlist.length;
    if (limit == 0) return;
    if (_shuffleHistory.isNotEmpty && _shuffleHistory.last == index) return;
    _shuffleHistory.add(index);
    while (_shuffleHistory.length > limit) {
      _shuffleHistory.removeAt(0);
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
        _pushShuffleHistory(state.currentIndex);
        nextIndex = _pickShuffledIndex();
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
      } else if (_shuffleHistory.isNotEmpty) {
        // 回到真正听过的那一首，而不是重新随机（随机回退必然重复）。
        prevIndex = _shuffleHistory.removeLast();
        if (prevIndex < 0 || prevIndex >= state.playlist.length) {
          prevIndex = state.currentIndex;
        }
      } else {
        _pushShuffleHistory(state.currentIndex);
        prevIndex = _pickShuffledIndex();
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

  /// Inserts [song] right after the current track ("下一首播放").
  ///
  /// Does **not** interrupt playback: this only rewrites the queue, it never
  /// touches the audio controller (no `stop`/`setUrl`/`play`), so the current
  /// track keeps playing untouched.
  ///
  /// Duplicate semantics: when the queue already holds the same
  /// `(id, platform)`, it is **moved** to the next position instead of being
  /// inserted a second time. Two reasons: (1) "播放下一首" means "I want to hear
  /// it right now", and a copy would leave the song in the queue twice; (2)
  /// [playSong] locates the current index by `(id, platform)`, so a duplicate
  /// makes that lookup point at the wrong row. If the song is already the
  /// current track or already sits at `currentIndex + 1`, this is a no-op.
  ///
  /// An empty queue — or a playlist whose `currentIndex` is unset — falls back
  /// to [addToQueue] so both entry points keep the same "append at the end,
  /// dedupe, do not autoplay" semantics.
  void playNext(Song song) {
    if (state.playlist.isEmpty || state.currentIndex < 0) {
      addToQueue(song);
      return;
    }

    final playlist = List<Song>.from(state.playlist);
    final currentIndex = state.currentIndex.clamp(0, playlist.length - 1);
    final existingIndex = playlist.indexWhere(
      (item) => item.id == song.id && item.platform == song.platform,
    );
    if (existingIndex == currentIndex) return;
    if (existingIndex == currentIndex + 1) return;

    var newIndex = currentIndex;
    if (existingIndex >= 0) {
      playlist.removeAt(existingIndex);
      // 被移动的曲目原来在当前位置之前时，当前曲目的下标要跟着左移一位。
      if (existingIndex < currentIndex) newIndex = currentIndex - 1;
    }
    playlist.insert(newIndex + 1, song);
    _setState(state.copyWith(playlist: playlist, currentIndex: newIndex));
    _schedulePlaybackMemorySave();
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
    _subscriptions.clear();
    _notificationController.detach();
    unawaited(_keepAliveController.dispose());
    // Null the reference immediately: listeners and `_ensureAudioController`
    // consult `_audioController`, and a disposed-but-still-referenced player
    // would be reused by anything that runs after `dispose()` (e.g. a pending
    // timer callback), resurrecting a dead platform channel.
    final controller = _audioController;
    _audioController = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }
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
    toggleFloatingLyrics: () =>
        ref.read(floatingLyricsProvider.notifier).toggleEnabled(),
    isFloatingLyricsEnabled: () => ref.read(floatingLyricsProvider).enabled,
    // 离线模式：只有开关打开时才优先本地文件，否则保持原有网络取流行为。
    // 解析器只在开关为真时才被调用（downloadProvider 因此是懒创建的）。
    isOfflineModeEnabled: () => ref.read(offlineCacheSettingsProvider).offlineMode,
    offlineFilePathResolver: (song) =>
        ref.read(downloadProvider.notifier).localFilePathFor(song),
  );
  ref.listen<List<Song>>(
    likesProvider.select((state) => state.songs),
    (_, _) => notifier.refreshNotificationState(),
  );
  ref.listen<bool>(
    floatingLyricsProvider.select((state) => state.enabled),
    (_, _) => notifier.refreshNotificationState(),
  );
  return notifier;
});
