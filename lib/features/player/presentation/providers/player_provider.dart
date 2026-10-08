import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' show AudioPlayer, ProcessingState;
import '../../../../core/diagnostics/diagnostics_service.dart';
import '../../../../core/network/api_exception.dart';
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

/// 播放失败的用户可见分级（Wave 0-A / item 2）。
///
/// 把"放不出来"分成三类：不可用 / 需要会员 / 网络，其余回落到原文。分级只影响
/// 提示文案与诊断字段，不影响失败链本身。
enum PlaybackFailureKind { unavailable, vipRequired, network, unknown }

/// 跨平台换源接缝（Wave 0-A / item 2）。
///
/// 传入"放不出来的那首歌"与"想再试一次的音质"，返回另一个源上可播的直链；
/// 返回 `null` 表示那边也没有。本波**不实现**真实换源：默认为 `null`，此时失败链
/// 就是「降一档音质 → skipToNext」，W1 再把实现接进来。
///
/// 用 [AudioLevel] 而不是 `AudioQuality`：整个播放面（`getSongUrl`、`switchQuality`、
/// `PlayerState.currentQuality`）的通用货币就是档位，换源方要的也正是"还能接受
/// 的最低档"。
typedef CrossSourceResolver =
    Future<String?> Function(Song song, AudioLevel quality);

/// 一次失败的 `playSong` 尝试，交给失败链处理（Wave 0-A / item 2）。
class _PlaybackFailure {
  const _PlaybackFailure({
    required this.song,
    required this.platform,
    required this.quality,
    required this.error,
    required this.requestId,
    required this.usedLocalFile,
  });

  final Song song;

  /// 该歌曲所属平台；本地曲目为 `null`。
  final MusicPlatform? platform;

  /// 这次尝试真正用的音质（降档从它往下走）。
  final AudioLevel quality;

  final Object error;
  final int requestId;

  /// 这次尝试用的是离线本地文件，降档/换源都无意义。
  final bool usedLocalFile;
}

/// 播放错误提示的去重器（Wave 0-A / item 1）。
///
/// `PlayerState.error` 有 14 处赋值，而 `/player` 是压在 shell 上的路由 ——
/// mini player 与全屏播放页**同时存活**，两边各自 `ref.listen` 同一个 error。
/// 如果各自弹一条，用户会在同一个错误上看到两条 SnackBar，所以去重状态放在共享
/// 实例里，而不是各 widget 自己一份。
class PlaybackErrorDeduper {
  String? _lastShown;

  /// 返回 true 表示 [error] 需要提示（并记住它）。
  ///
  /// `null`/空串表示"错误已被清除"：重置记忆，使之后**同一条**错误能再次提示。
  bool shouldAnnounce(String? error) {
    if (error == null || error.isEmpty) {
      _lastShown = null;
      return false;
    }
    if (error == _lastShown) return false;
    _lastShown = error;
    return true;
  }
}

/// 全 app 共享的错误提示去重状态（见 [PlaybackErrorDeduper]）。
final playbackErrorDeduper = PlaybackErrorDeduper();

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
///
/// It stays the **single** serialization point (running transport calls
/// concurrently is what deadlocks just_audio's platform channel), but it is no
/// longer unbounded: a wedged holder used to block every later tap at
/// `await prev` forever, which is exactly the "app freezes, must be force-killed"
/// chain from the device logs (frozen `position_ms`, `is_playing:false`,
/// six process restarts in eight minutes).
class _AudioMutex {
  _AudioMutex({
    this.onWedged,
    this.waitTimeout = const Duration(seconds: 8),
    this.maxPending = 8,
  });

  /// Invoked (fire-and-forget) when waiting for the previous holder timed out.
  final void Function(String label, int waitedMs)? onWedged;

  /// How long a waiter may block on the previous holder before it gives up and
  /// runs its own operation anyway. Every inner await of a healthy operation is
  /// bounded by its own timeout (≤10s), so exceeding this means a wedge.
  final Duration waitTimeout;

  /// Upper bound on queued waiters. Past it a waiter stops waiting (and a
  /// diagnostic is recorded) instead of growing an unbounded chain.
  final int maxPending;

  Future<void>? _last;
  int _pending = 0;

  @visibleForTesting
  int get pendingCount => _pending;

  Future<T> run<T>(Future<T> Function() fn, {String label = 'audio'}) async {
    final completer = Completer<void>();
    final prev = _last;
    _last = completer.future;
    // The `try` (and therefore the `finally`) covers everything after the
    // completer is published: a synchronous throw can no longer leave
    // `_last` pointing at a future that is never completed, which used to
    // strand every subsequent waiter forever.
    final wait = Stopwatch()..start();
    _pending++;
    try {
      if (prev != null) {
        if (_pending > maxPending) {
          // 队列超出上界：不再等待，直接执行本次操作并记诊断。
          // （无法"踢掉"已经在 await 上的最老等待者；而它的等待本身也会先于
          // 本调用被 waitTimeout 解开，所以这里放弃等待即可给队列封顶。）
          DiagnosticsService.instance.record(
            'slow_operation',
            'audio_mutex_overflow',
            data: {
              'label': label,
              'pending': _pending,
              'max_pending': maxPending,
            },
          );
        } else {
          try {
            await prev.timeout(waitTimeout);
          } on TimeoutException {
            DiagnosticsService.instance.record(
              'player',
              'audio_mutex_wedged',
              data: {
                'label': label,
                'waited_ms': wait.elapsedMilliseconds,
                'timeout_ms': waitTimeout.inMilliseconds,
              },
            );
            onWedged?.call(label, wait.elapsedMilliseconds);
          }
        }
      }
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
      _pending--;
      if (!completer.isCompleted) completer.complete();
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
  final Duration _mutexWaitTimeout;
  final int _mutexMaxPending;
  final Duration _stuckWatchdogInterval;
  final Duration _stuckWatchdogThreshold;
  final DateTime Function() _now;
  final PlayerPlaybackMemoryStore _playbackMemoryStore;
  final playback_notification.PlaybackNotificationController
  _notificationController;
  final PlaybackKeepAliveController _keepAliveController;
  final SongLikeResolver _isSongLiked;
  final SongLikeToggle? _toggleSongLike;
  final OfflineFilePathResolver? _offlineFilePathResolver;

  /// 跨平台换源接缝；`null` 时失败链只有「降档 → 跳曲」（Wave 0-A / item 2）。
  final CrossSourceResolver? _crossSourceResolver;

  /// 失败链最多连续跳几首，防止"整张队列都取不到流"时无限跳（见 [_failureChainSkips]）。
  final int _maxFailureChainSkips;

  final bool Function() _isOfflineModeEnabled;
  final Future<void> Function()? _toggleFloatingLyrics;
  final bool Function() _isFloatingLyricsEnabled;
  final List<StreamSubscription> _subscriptions = [];
  late final _AudioMutex _mutex = _AudioMutex(
    waitTimeout: _mutexWaitTimeout,
    maxPending: _mutexMaxPending,
    onWedged: _onAudioMutexWedged,
  );
  final Random _random;
  /// 随机播放的"已播集合"（本轮尚未播过的曲目之外不再挑）。
  final Set<String> _shuffledPlayedSongKeys = {};
  /// 随机播放的历史栈，供 skipToPrevious 回到真正听过的那首。
  final List<int> _shuffleHistory = [];
  bool _isSwitchingQuality = false;
  bool _restoredSourceNeedsLoad = false;
  bool _isDisposed = false;
  int _lastPositionSecond = -1;
  int _playRequestId = 0;
  int _qualityRequestId = 0;

  /// 失败链连续跳了几首（Wave 0-A / item 2）。
  ///
  /// 没有它，`repeat: all` + 整张队列都取不到流时，每次失败都 skip 到下一首、
  /// 下一首又失败……把一个"错误提示"变成一台无限重试机器。任何一次成功播放清零。
  int _failureChainSkips = 0;

  /// 喜欢歌曲的 key 集合，由 [updateLikedSongs] 增量维护（P-1）。
  final Set<String> _likedSongKeys = {};

  /// 是否已经收到过整份喜欢列表。未收到时回落到注入的 [_isSongLiked]。
  bool _hasLikedSongKeys = false;
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
  Timer? _stuckWatchdogTimer;
  DateTime? _lastTransportProgressAt;
  bool _isForcingReset = false;
  Future<void>? _recreateInFlight;

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
    this._crossSourceResolver,
    this._maxFailureChainSkips = 3,
    bool Function()? isOfflineModeEnabled,
    this._toggleFloatingLyrics,
    bool Function()? isFloatingLyricsEnabled,
    this._playbackHealthCheckInterval = const Duration(seconds: 5),
    this._playbackStallThreshold = const Duration(seconds: 12),
    this._playbackRecoveryCooldown = const Duration(seconds: 30),
    this._playbackStartupGracePeriod = const Duration(seconds: 8),
    this._mutexWaitTimeout = const Duration(seconds: 8),
    this._mutexMaxPending = 8,
    this._stuckWatchdogInterval = const Duration(seconds: 5),
    this._stuckWatchdogThreshold = const Duration(seconds: 30),
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
    _startStuckWatchdog();
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
    _markTransportProgress();
    _syncNotificationState();
    unawaited(_syncPlaybackKeepAlive(nextState.isPlaying));
  }

  /// Records that the transport did something observable.
  ///
  /// The stuck watchdog (see [_checkStuckTransport]) only fires when *nothing*
  /// has progressed for [_stuckWatchdogThreshold], so every real state change —
  /// position, processing state, request generation, flags — has to rearm it.
  void _markTransportProgress() {
    _lastTransportProgressAt = _now();
  }

  void _syncNotificationState() {
    _notificationController.update(
      currentSong: state.currentSong,
      playlist: state.playlist,
      currentIndex: state.currentIndex,
      isCurrentSongLiked:
          state.currentSong != null &&
          _isCurrentSongLikedNow(state.currentSong!),
      isFloatingLyricsEnabled: _isFloatingLyricsEnabled(),
      isPlaying: state.isPlaying,
      position: state.position,
      duration: state.duration,
    );
  }

  /// `(platform, id)` 形式的喜欢键。
  ///
  /// 与 `likes_provider.dart` 里 `'${platform}_${id}'` 的拼法同构，也与本文件的
  /// [_songKey] 同义。用 id+platform 而不是 `Song.dedupeKey`：喜欢列表是按
  /// `(id, platform)` 存的（见 `LikesNotifier.toggleLike`），用 dedupeKey 会把
  /// 同一首歌在另一个平台上的条目也判成"已喜欢"。
  static String likedSongKeyFor(Song song) =>
      '${song.platform.name}_${song.id}';

  /// 用整份喜欢列表刷新 key 集合（Wave 0-A / P-1）。
  ///
  /// 以前 `playerProvider` 把 `likesProvider.songs.any(...)`（最多 500 首）当
  /// [SongLikeResolver] 传进来，而它**每秒**都会被调一次（位置 tick → 状态更新 →
  /// 通知刷新，Windows 也一样）→ 每秒一次 O(n)。现在只在喜欢列表变化时重建一次
  /// `Set`，热路径上只剩一次 `Set.contains`。
  void updateLikedSongs(Iterable<Song> songs) {
    _likedSongKeys
      ..clear()
      ..addAll(songs.map(likedSongKeyFor));
    _hasLikedSongKeys = true;
    _syncNotificationState();
  }

  bool _isCurrentSongLikedNow(Song song) {
    if (_hasLikedSongKeys) {
      return _likedSongKeys.contains(likedSongKeyFor(song));
    }
    // 兜底：只有从未调用 [updateLikedSongs] 的构造方式（单测、嵌套用例）才走这里。
    return _isSongLiked(song);
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

  @visibleForTesting
  Future<void> runStuckWatchdogForTest() => _checkStuckTransport();

  /// True while any transport-level flag is latched.
  @visibleForTesting
  bool get isTransportBusyForTest =>
      state.isTransitioning ||
      _isSwitchingQuality ||
      _isRecoveringPlayback ||
      _restoredSourceNeedsLoad;

  // --- 卡死看门狗（独立于 12s 转场看门狗） -------------------------------
  //
  // 与 12s 停滞自愈的区别：后者只服务"Android + isPlaying + 在线歌曲"的
  // 位置停滞，而真机日志里的死法是 `is_playing:false` + 位置冻住 —— 那时
  // `_canCheckPlaybackHealth` 与新加的 `_ensurePlaybackVolume` 都因为
  // `isPlaying` 为假而永不触发。因此这条看门狗**不以 isPlaying 为前提**：
  // 只要"有当前曲目 + 处于过渡/换音质/恢复中 + 超过阈值没有任何位置或状态
  // 推进"，就强制把播放面复位到可用状态。

  void _startStuckWatchdog() {
    if (_stuckWatchdogInterval <= Duration.zero) return;
    _stuckWatchdogTimer = Timer.periodic(
      _stuckWatchdogInterval,
      (_) => unawaited(_checkStuckTransport()),
    );
  }

  bool _isTransportSuspicious() {
    if (state.currentSong == null) return false;
    return state.isTransitioning ||
        _isSwitchingQuality ||
        _isRecoveringPlayback ||
        _restoredSourceNeedsLoad;
  }

  Future<void> _checkStuckTransport() async {
    if (!mounted || _isForcingReset) return;
    if (!_isTransportSuspicious()) {
      // 正常播放（或空闲）：重新起算，避免把长时间的普通播放当成卡死。
      _markTransportProgress();
      return;
    }
    final last = _lastTransportProgressAt;
    if (last == null) {
      _markTransportProgress();
      return;
    }
    if (_now().difference(last) < _stuckWatchdogThreshold) return;
    await _forceResetStuckPlayback('transport_stuck');
  }

  /// 强制把播放面复位到"可再次操作"的状态。
  ///
  /// 由看门狗或 [_AudioMutex] 超时触发（两者都可能发生在**没有**持锁的情况下，
  /// 所以这里绝不进入 `_AudioMutex` —— 那正是卡死的源头）。复位会推进两个代际
  /// 令牌，让所有在途的陈旧分支在下一个守卫处立刻退出。
  Future<void> _forceResetStuckPlayback(String reason) async {
    if (!mounted || _isForcingReset) return;
    _isForcingReset = true;
    try {
      final song = state.currentSong;
      DiagnosticsService.instance.record(
        'player',
        'player_forced_reset',
        data: {
          'reason': reason,
          'song_id': song?.id,
          'platform': song?.platform.name,
          'is_playing': state.isPlaying,
          'is_transitioning': state.isTransitioning,
          'is_switching_quality': _isSwitchingQuality,
          'is_recovering': _isRecoveringPlayback,
          'restored_source_needs_load': _restoredSourceNeedsLoad,
          'position_ms': state.position.inMilliseconds,
        },
      );
      _playRequestId++;
      _qualityRequestId++;
      _isSwitchingQuality = false;
      _isRecoveringPlayback = false;
      _restoredSourceNeedsLoad = false;
      _cancelTransitionWatchdog();
      _setState(
        state.copyWith(
          isTransitioning: false,
          error: () => '播放未能恢复，已重置播放器，请重试',
        ),
      );
      _resetPlaybackHealthWindow(applyGrace: true);
      await _recreatePlayer();
    } finally {
      _isForcingReset = false;
      _markTransportProgress();
    }
  }

  void _onAudioMutexWedged(String label, int waitedMs) {
    debugPrint(
      'PlayerNotifier: audio mutex wedged on "$label" after ${waitedMs}ms, forcing reset',
    );
    unawaited(_forceResetStuckPlayback('audio_mutex_wedged:$label'));
  }

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
          // A-2：播放偏好和"上次播到哪"一起恢复。
          playbackSpeed: memory.playbackSpeed,
          skipSilence: memory.skipSilence,
          isShuffle: memory.isShuffle,
          repeatMode: _repeatModeFromName(memory.repeatMode),
          abLoopStart: () => memory.abLoopStart,
          abLoopEnd: () => memory.abLoopEnd,
          error: () => null,
          isTransitioning: false,
        ),
      );
      await _applyRestoredPreferencesToController();
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
      // A-2：偏好跟着一起落盘，任何一次 [_schedulePlaybackMemorySave] 都会带上。
      playbackSpeed: state.playbackSpeed,
      skipSilence: state.skipSilence,
      isShuffle: state.isShuffle,
      repeatMode: state.repeatMode.name,
      abLoopStart: state.abLoopStart,
      abLoopEnd: state.abLoopEnd,
    );
  }

  RepeatMode _repeatModeFromName(String name) {
    return RepeatMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => RepeatMode.off,
    );
  }

  /// 把恢复出来的偏好推给**已经存在**的控制器。
  ///
  /// 全新控制器不需要这一步：[`_restoreControllerAudioSettings`] 会在创建/重建时
  /// 把 `state.playbackSpeed` / `state.skipSilence` 推过去。这里只覆盖"启动时已经
  /// 有注入控制器"的情况（测试与热重建）。
  Future<void> _applyRestoredPreferencesToController() async {
    final controller = _audioController;
    if (controller == null) return;
    if (controller is PlaybackSpeedCapable && state.playbackSpeed != 1.0) {
      try {
        await (controller as PlaybackSpeedCapable)
            .setPlaybackSpeed(state.playbackSpeed)
            .timeout(_audioOperationTimeout);
      } catch (e) {
        debugPrint('PlayerNotifier restore speed failed: $e');
      }
    }
    if (controller is SkipSilenceCapable && state.skipSilence) {
      try {
        await (controller as SkipSilenceCapable)
            .setSkipSilence(true)
            .timeout(_audioOperationTimeout);
      } catch (e) {
        debugPrint('PlayerNotifier restore skip silence failed: $e');
      }
    }
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
    final memory = _takePlaybackMemorySnapshot();
    if (memory == null) return;
    await _savePlaybackMemory(memory);
  }

  /// 同步取出待落盘的快照，并清掉挂起的定时器。
  ///
  /// **必须同步**：快照要读 `state`，而 `StateNotifier` 在 `dispose()` 之后会对
  /// `state` 抛 "Tried to use ... after `dispose` was called"。以前 `dispose()` 里
  /// 直接 `unawaited(flushPlaybackMemory())`，快照是在那个异步体的同步段里构造的
  /// —— 只要 `dispose()` 被走到第二次（Riverpod 随 scope 销毁一次、宿主/测试收尾
  /// 再销毁一次），第二次就会读到已失效的 `state` 并抛异常（widget 用例就是这样
  /// 被带崩的）。
  PlayerPlaybackMemory? _takePlaybackMemorySnapshot() {
    final memory = _pendingPlaybackMemory ?? _buildPlaybackMemory();
    _pendingPlaybackMemory = null;
    _playbackMemoryTimer?.cancel();
    _playbackMemoryTimer = null;
    return memory;
  }

  Future<void> _savePlaybackMemory(PlayerPlaybackMemory memory) async {
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
      _schedulePlaybackMemorySave();
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
      _schedulePlaybackMemorySave();
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
      _schedulePlaybackMemorySave();
      return;
    }
    _setState(state.copyWith(abLoopStart: () => start));
    _schedulePlaybackMemorySave();
  }

  void setAbLoopEnd([Duration? position]) {
    final end = position ?? state.position;
    final start = state.abLoopStart;
    if (start == null || end <= start) {
      _setState(state.copyWith(error: () => 'B 点必须晚于 A 点'));
      return;
    }
    _setState(state.copyWith(abLoopEnd: () => end, error: () => null));
    _schedulePlaybackMemorySave();
  }

  void clearAbLoop() {
    if (!state.hasAbLoop && state.abLoopStart == null) return;
    _setState(state.copyWith(abLoopStart: () => null, abLoopEnd: () => null));
    _schedulePlaybackMemorySave();
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
      // 只看全局的 isTransitioning，不再要求 `requestId == _playRequestId`：
      // 当新请求已经推进了 id 却卡在队列里时，旧看门狗会被这个守卫拒绝复位，
      // 于是该标志永久为真，连带把三处门禁（健康检查/音量守护/通知）永久关掉。
      if (!mounted || !state.isTransitioning) {
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
      _markTransportProgress();
    });
  }

  void _cancelTransitionWatchdog() {
    _transitionWatchdog?.cancel();
    _transitionWatchdog = null;
  }

  /// Recreate the AudioPlayer when the platform channel is corrupted.
  ///
  /// Single-flight: all seven trigger points (the `_safeStop`/`_safeSeek`
  /// failure paths, `_handleAsyncPlayError`, `setUrl` retries and the forced
  /// reset) funnel through here, and several are fire-and-forget. Without the
  /// guard two concurrent rebuilds cancelled each other's subscriptions and
  /// installed two controllers — the "double instance / crossed audio" defect
  /// behind the freeze reports.
  Future<void> _recreatePlayer() {
    final inFlight = _recreateInFlight;
    if (inFlight != null) return inFlight;

    final completer = Completer<void>();
    // Publish before doing any work so a re-entrant caller (even a synchronous
    // one) always observes the in-flight future.
    _recreateInFlight = completer.future;
    unawaited(() async {
      try {
        await _doRecreatePlayer();
      } catch (e, s) {
        debugPrint('PlayerNotifier recreate failed: $e');
        DiagnosticsService.instance.recordError('player.recreatePlayer', e, s);
      } finally {
        _recreateInFlight = null;
        if (!completer.isCompleted) completer.complete();
      }
    }());
    return completer.future;
  }

  Future<void> _doRecreatePlayer() async {
    if (!mounted) return;
    debugPrint('PlayerNotifier: recreating AudioPlayer');
    final previous = _audioController;
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    try {
      await previous?.dispose().timeout(_audioDisposeTimeout);
    } catch (e) {
      debugPrint('PlayerNotifier dispose during recreate failed: $e');
    }
    // 期间可能已被 dispose()（置空）或已有人装了更新的 controller —— 两种情况下
    // 都不许再替换，否则会复活死掉的平台通道 / 丢掉正在用的实例。
    if (!mounted) return;
    if (!identical(_audioController, previous)) return;
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
    // 失败链**必须**在锁外跑（Wave 0-A / item 2）：链尾的 skipToNext 会再进
    // [_mutex]，而锁不可重入（等待者会在 waitTimeout 后判定"卡死"并强复位）。
    // 所以锁内的 playSong 只负责"这一次尝试"，失败就把它作为结果交给锁外的链。
    final failure = await _mutex.run<_PlaybackFailure?>(() async {
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
      // 失败链要用的上下文：这次尝试用的音质、以及是不是走的离线本地文件。
      var attemptedQuality = state.currentQuality;
      var usedLocalFile = false;
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
        // 这个闭包返回 `_PlaybackFailure?`：`null` = 这次尝试没有失败（或已被
        // 更新的请求取代），有值 = 交给锁外的失败链处理。
        if (requestId != _playRequestId) return null;

        final String url;
        if (offlineUrl != null) {
          url = offlineUrl;
          usedLocalFile = true;
        } else {
          final playbackQuality = await _resolvePlaybackQuality(song, platform);
          if (requestId != _playRequestId) return null;
          attemptedQuality = playbackQuality;
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
        if (requestId != _playRequestId) return null;

        // CRITICAL: stop() before setUrl() to release the previous platform player
        await _safeStop();
        if (requestId != _playRequestId) return null;

        await _setUrlWithRecovery(url, 'playSong');
        debugPrint('playSong: setUrl done');
        if (requestId != _playRequestId) return null;

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
        // 成功路径（以及"已被更新请求取代"）都要显式返回 null：这个闭包的返回
        // 类型是 `_PlaybackFailure?`，否则 analyzer 会报"ends without returning"。
        return null;
      } catch (e, s) {
        // 陈旧请求：新的 playSong 已经在推进，本次失败不再有任何后续动作。
        if (requestId != _playRequestId) return null;
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
        return _PlaybackFailure(
          song: song,
          platform: platform,
          quality: attemptedQuality,
          error: e,
          requestId: requestId,
          usedLocalFile: usedLocalFile,
        );
      }
    }, label: 'playSong');

    if (failure == null) {
      // 有一次成功播放就把"连续失败"计数清零。
      _failureChainSkips = 0;
      return;
    }
    await _runPlaybackFailureChain(failure);
  }

  // ── 播放失败链（Wave 0-A / item 2） ─────────────────────────────────────
  //
  // 以前 playSong 失败只是 `_setState(error: ...)`：队列里明明还有下一首，用户
  // 却只能停在一首永远放不出来的歌上。现在的顺序是
  //   ① 降一档音质重试 → ② 可注入的跨平台换源（本波默认 null）→ ③ skipToNext
  // 每一步都写 DiagnosticsService，真机上才有可能复盘"这首歌为什么放不出来"。

  Future<void> _runPlaybackFailureChain(_PlaybackFailure failure) async {
    if (!mounted || failure.requestId != _playRequestId) return;
    final notice = _playbackFailureNotice(failure.error);
    DiagnosticsService.instance.record(
      'player',
      'playback_failure_chain_start',
      data: {
        'song_id': failure.song.id,
        'platform': failure.song.platform.name,
        'quality': failure.quality.name,
        'local_file': failure.usedLocalFile,
        'kind': _classifyPlaybackFailure(failure.error).name,
      },
    );

    // 离线本地文件放不出来时降档/换源都没有意义（没有"另一个码率的本地文件"）。
    final canTryOtherSources =
        !failure.usedLocalFile &&
        failure.song.platform != PlatformType.local &&
        failure.platform != null;
    if (canTryOtherSources) {
      if (await _retryPlaybackWithLowerQuality(failure)) {
        _failureChainSkips = 0;
        return;
      }
      if (await _retryPlaybackWithCrossSource(failure)) {
        _failureChainSkips = 0;
        return;
      }
    }

    await _giveUpOnFailedPlayback(failure, notice);
  }

  /// ① 降一档音质：从这次用的档位往下逐级试，任一级取到流就重新起播。
  Future<bool> _retryPlaybackWithLowerQuality(_PlaybackFailure failure) async {
    final platform = failure.platform;
    if (platform == null) return false;
    for (final quality in _lowerQualityLevels(failure.quality)) {
      if (!mounted || failure.requestId != _playRequestId) return false;
      DiagnosticsService.instance.record(
        'player',
        'playback_failure_downshift_attempt',
        data: {
          'song_id': failure.song.id,
          'platform': failure.song.platform.name,
          'from': failure.quality.name,
          'to': quality.name,
        },
      );
      try {
        final url = await DiagnosticsService.instance.measure(
          'platform.getSongUrl.failureDownshift',
          () => platform
              .getSongUrl(failure.song.id, quality: quality)
              .timeout(const Duration(seconds: 10)),
          data: {'song_id': failure.song.id, 'quality': quality.name},
        );
        if (!mounted || failure.requestId != _playRequestId) return false;
        if (url.trim().isEmpty) continue;
        if (await _playResolvedUrl(failure, url, quality, 'downshift')) {
          DiagnosticsService.instance.record(
            'player',
            'playback_failure_downshift_success',
            data: {
              'song_id': failure.song.id,
              'from': failure.quality.name,
              'to': quality.name,
            },
          );
          return true;
        }
      } catch (error, stack) {
        DiagnosticsService.instance.recordError(
          'player.playbackFailureDownshift',
          error,
          stack,
          data: {'song_id': failure.song.id, 'quality': quality.name},
        );
      }
    }
    return false;
  }

  /// ② 跨平台换源。本波 [_crossSourceResolver] 默认为 `null`（W1 才接真实实现），
  /// 此时这一步直接跳过，链就是「降档 → skipToNext」。
  Future<bool> _retryPlaybackWithCrossSource(_PlaybackFailure failure) async {
    final resolver = _crossSourceResolver;
    if (resolver == null) return false;
    final qualities = <AudioLevel>[
      failure.quality,
      ..._lowerQualityLevels(failure.quality),
    ];
    for (final quality in qualities) {
      if (!mounted || failure.requestId != _playRequestId) return false;
      DiagnosticsService.instance.record(
        'player',
        'playback_failure_cross_source_attempt',
        data: {
          'song_id': failure.song.id,
          'platform': failure.song.platform.name,
          'quality': quality.name,
        },
      );
      try {
        final url = await resolver(failure.song, quality);
        if (!mounted || failure.requestId != _playRequestId) return false;
        if (url == null || url.trim().isEmpty) continue;
        if (await _playResolvedUrl(failure, url, quality, 'crossSource')) {
          DiagnosticsService.instance.record(
            'player',
            'playback_failure_cross_source_success',
            data: {'song_id': failure.song.id, 'quality': quality.name},
          );
          return true;
        }
      } catch (error, stack) {
        DiagnosticsService.instance.recordError(
          'player.playbackFailureCrossSource',
          error,
          stack,
          data: {'song_id': failure.song.id, 'quality': quality.name},
        );
      }
    }
    return false;
  }

  /// 用换来的直链重新起播；成功返回 true。
  Future<bool> _playResolvedUrl(
    _PlaybackFailure failure,
    String url,
    AudioLevel quality,
    String label,
  ) {
    // 同样在锁外调用（失败链整体在锁外），这里再进一次锁是安全的。
    return _mutex.run(() async {
      if (!mounted || failure.requestId != _playRequestId) return false;
      try {
        final fadeGeneration = _cancelActiveFades();
        await _safeStop();
        if (!mounted || failure.requestId != _playRequestId) return false;
        await _setUrlWithRecovery(url, 'failureChain.$label');
        if (!mounted || failure.requestId != _playRequestId) return false;
        _safePlay(requestId: failure.requestId);
        unawaited(_runFade(from: 0, to: 1, generation: fadeGeneration));
        _schedulePlaybackVolumeRecovery(fadeGeneration);
        _setState(
          state.copyWith(
            currentQuality: quality,
            isPlaying: true,
            isTransitioning: false,
            error: () => null,
          ),
        );
        _resetPlaybackHealthWindow(applyGrace: true);
        _schedulePlaybackMemorySave();
        _cancelTransitionWatchdog();
        return true;
      } catch (error, stack) {
        DiagnosticsService.instance.recordError(
          'player.playbackFailureRetry',
          error,
          stack,
          data: {'song_id': failure.song.id, 'label': label},
        );
        return false;
      }
    }, label: 'failureChain.$label');
  }

  /// ③ 全失败：能跳就跳下一首，队列里没有下一首时只提示、不跳。
  Future<void> _giveUpOnFailedPlayback(
    _PlaybackFailure failure,
    String notice,
  ) async {
    if (!mounted || failure.requestId != _playRequestId) return;
    final canSkip = _canSkipAfterPlaybackFailure();
    DiagnosticsService.instance.record(
      'player',
      'playback_failure_chain_exhausted',
      data: {
        'song_id': failure.song.id,
        'platform': failure.song.platform.name,
        'quality': failure.quality.name,
        'can_skip': canSkip,
        'skips': _failureChainSkips,
      },
    );
    if (canSkip) {
      _failureChainSkips++;
      DiagnosticsService.instance.record(
        'player',
        'playback_failure_skip_next',
        data: {
          'song_id': failure.song.id,
          'index': state.currentIndex,
          'skips': _failureChainSkips,
        },
      );
      await skipToNext();
      if (!mounted) return;
    }
    // 错误必须在 skipToNext **之后**写：playSong 一开始就会 `error: () => null`，
    // 先写会被它抹掉 —— 那样"这首歌放不出来、已经跳下一首"对用户彻底不可见。
    _setState(
      state.copyWith(
        isPlaying: canSkip ? state.isPlaying : false,
        isTransitioning: false,
        error: () => canSkip ? '$notice，已跳到下一首' : notice,
      ),
    );
  }

  /// 队列里还有没有"可跳的下一首"。
  ///
  /// 三个例外都返回 false：只剩这一首、单曲循环（跳等于重放坏歌）、失败链已经连续
  /// 跳了 [_maxFailureChainSkips] 次（`repeat: all` + 全队列取不到流时不能无限跳）。
  bool _canSkipAfterPlaybackFailure() {
    if (_failureChainSkips >= _maxFailureChainSkips) return false;
    if (state.repeatMode == RepeatMode.one) return false;
    final playlist = state.playlist;
    if (playlist.length <= 1 || state.currentIndex < 0) return false;
    if (state.isShuffle) return true;
    if (state.currentIndex + 1 < playlist.length) return true;
    return state.repeatMode == RepeatMode.all;
  }

  /// [quality] 之下（更省流）的所有档位，从高到低。
  List<AudioLevel> _lowerQualityLevels(AudioLevel quality) {
    return [
      for (final level in AudioLevel.values)
        if (level.index < quality.index) level,
    ].reversed.toList(growable: false);
  }

  PlaybackFailureKind _classifyPlaybackFailure(Object error) {
    if (error is TimeoutException) return PlaybackFailureKind.network;
    final exception = apiExceptionOf(error);
    if (exception is NetworkException) return PlaybackFailureKind.network;
    if (exception is NoVipMembershipException) {
      return PlaybackFailureKind.vipRequired;
    }
    if (exception is SongNotAvailableException ||
        exception is QualityNotAvailableException ||
        exception is NotFoundException ||
        exception is LoginExpiredException) {
      return PlaybackFailureKind.unavailable;
    }
    if (exception.statusCode != null && exception.statusCode! >= 500) {
      return PlaybackFailureKind.network;
    }
    return PlaybackFailureKind.unknown;
  }

  /// 分级提示：不可用 / 需会员 / 网络；认不出来的失败不把 Dart 内部错误抛给用户。
  String _playbackFailureNotice(Object error) {
    final exception = apiExceptionOf(error);
    return switch (_classifyPlaybackFailure(error)) {
      PlaybackFailureKind.network => '网络连接失败，请检查网络后重试',
      PlaybackFailureKind.vipRequired => exception.message,
      PlaybackFailureKind.unavailable => exception.message,
      PlaybackFailureKind.unknown => '播放失败，请稍后重试',
    };
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
        // 失败路径也必须清掉这个标志：它只在成功路径被写 false 时，恢复失败会让
        // 之后每次 togglePlay 都重新进入这条必然失败的路径，同时把
        // `_canCheckPlaybackHealth` 的 `!_restoredSourceNeedsLoad` 门禁永久关死。
        _restoredSourceNeedsLoad = false;
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
    _schedulePlaybackMemorySave();
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
    _schedulePlaybackMemorySave();
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

  // ── 队列编辑 API（Wave 0-A / item 7；W1-D 的队列页要用） ───────────────

  /// 从队列里移除所有 [dedupeKey] 命中的曲目。
  ///
  /// [dedupeKey] 用 `Song.dedupeKey`（跨平台去重键），不是 `(id, platform)`：
  /// 队列里同一首歌来自两个平台时，"从队列移除这首歌"应当把两份都拿掉。
  ///
  /// 语义：
  /// * 当前曲目没被移除 → 只改队列，不碰播放器；
  /// * 当前曲目被移除 → 由"原下标位置上剩下的那一首"接手播放（在末尾则取新的
  ///   最后一首）；
  /// * 队列被清空 → 等价于 [clearQueue]（停止播放并清掉当前曲目）。
  Future<void> removeFromQueue(String dedupeKey) async {
    final playlist = state.playlist;
    if (playlist.isEmpty) return;
    final removedIndexes = <int>[
      for (var i = 0; i < playlist.length; i++)
        if (playlist[i].dedupeKey == dedupeKey) i,
    ];
    if (removedIndexes.isEmpty) return;

    final remaining = <Song>[
      for (var i = 0; i < playlist.length; i++)
        if (!removedIndexes.contains(i)) playlist[i],
    ];
    if (remaining.isEmpty) {
      await clearQueue();
      return;
    }

    final currentIndex = state.currentIndex;
    final removesCurrentSong =
        currentIndex >= 0 &&
        currentIndex < playlist.length &&
        removedIndexes.contains(currentIndex);
    if (!removesCurrentSong) {
      final current = state.currentSong;
      final newIndex = current == null
          ? state.currentIndex
          : remaining.indexWhere(
              (song) =>
                  song.id == current.id && song.platform == current.platform,
            );
      _setState(
        state.copyWith(
          playlist: remaining,
          currentIndex: newIndex < 0 ? state.currentIndex : newIndex,
        ),
      );
      _schedulePlaybackMemorySave();
      return;
    }

    // 当前曲目被移除：先让队列反映删除结果，再由接手的那一首重新起播。
    final handoverIndex = currentIndex.clamp(0, remaining.length - 1);
    _setState(
      state.copyWith(playlist: remaining, currentIndex: handoverIndex),
    );
    _schedulePlaybackMemorySave();
    await playSong(remaining[handoverIndex]);
  }

  /// 清空队列并停止播放。
  ///
  /// 与 `removeFromQueue(最后一首)` 完全一致：队列为空时就不该再有一首"当前曲目"
  /// 继续播下去。同时清掉落盘的播放记忆，否则重启后会把用户刚清掉的歌恢复回来。
  Future<void> clearQueue() async {
    if (state.playlist.isEmpty && state.currentSong == null) return;
    _playRequestId++;
    _qualityRequestId++;
    _isSwitchingQuality = false;
    _isRecoveringPlayback = false;
    _restoredSourceNeedsLoad = false;
    _failureChainSkips = 0;
    _cancelTransitionWatchdog();
    _cancelActiveFades();
    await _mutex.run(() => _safeStop(), label: 'clearQueue');
    if (!mounted) return;
    _resetShuffleBookkeeping();
    _lastPositionSecond = -1;
    _setState(
      PlayerState(
        currentQuality: state.currentQuality,
        qualityPreference: state.qualityPreference,
        playbackSpeed: state.playbackSpeed,
        skipSilence: state.skipSilence,
        isShuffle: state.isShuffle,
        repeatMode: state.repeatMode,
      ),
    );
    await _clearPlaybackMemory();
  }

  /// 把队列里第 [from] 首移动到第 [to] 位（[to] 是移动**之后**的下标）。
  ///
  /// 只重排队列，**不碰播放器**（不 stop/setUrl/play），所以正在播的那一首不会
  /// 被打断；[PlayerState.currentIndex] 跟着当前曲目一起移动。越界是 no-op。
  void moveInQueue(int from, int to) {
    final playlist = state.playlist;
    if (from < 0 || from >= playlist.length) return;
    if (to < 0 || to >= playlist.length) return;
    if (from == to) return;
    final reordered = List<Song>.from(playlist);
    final moved = reordered.removeAt(from);
    reordered.insert(to, moved);
    final current = state.currentSong;
    final newIndex = current == null
        ? state.currentIndex
        : reordered.indexWhere(
            (song) => song.id == current.id && song.platform == current.platform,
          );
    _setState(
      state.copyWith(
        playlist: reordered,
        currentIndex: newIndex < 0 ? state.currentIndex : newIndex,
      ),
    );
    _schedulePlaybackMemorySave();
  }

  /// 播放队列里的第 [index] 首。越界是 no-op。
  Future<void> playAtIndex(int index) async {
    final playlist = state.playlist;
    if (index < 0 || index >= playlist.length) return;
    await playSong(playlist[index]);
  }

  Future<void> _clearPlaybackMemory() async {
    _pendingPlaybackMemory = null;
    _playbackMemoryTimer?.cancel();
    _playbackMemoryTimer = null;
    try {
      await _playbackMemoryStore.clear();
    } catch (e, s) {
      debugPrint('PlayerNotifier clear playback memory failed: $e');
      debugPrint('$s');
    }
  }

  @override
  void dispose() {
    // Riverpod 会随 scope 销毁 notifier，宿主/测试收尾还可能再销毁一次；第二次必须
    // 是 no-op —— 已 dispose 的 `state` 不可读（见 [_takePlaybackMemorySnapshot]）。
    if (_isDisposed) return;
    _isDisposed = true;
    _cancelTransitionWatchdog();
    _stuckWatchdogTimer?.cancel();
    _stuckWatchdogTimer = null;
    _playbackMemoryTimer?.cancel();
    _playbackHealthTimer?.cancel();
    // 快照必须在 super.dispose() 之前**同步**取好（它读 state）；只有落盘可以
    // fire-and-forget。
    final memory = _takePlaybackMemorySnapshot();
    if (memory != null) {
      unawaited(_savePlaybackMemory(memory));
    }
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
    // P-1：喜欢状态不再走"每秒问一遍 likesProvider.songs.any(...)"的回调（最多
    // 500 首 × 每秒一次，Windows 也一样），改成下面 seed + 增量推送 key 集合。
    // 本波也不传 crossSourceResolver：默认 null，失败链就是「降档 → skipToNext」，
    // W1 再把真实换源接进来。
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
  // 先把当前喜欢列表灌进 key 集合（首次构建时通常还是空的，加载完成后由下面的
  // listener 再灌一次），此后热路径上只剩一次 `Set.contains`。
  notifier.updateLikedSongs(ref.read(likesProvider).songs);
  ref.listen<List<Song>>(
    likesProvider.select((state) => state.songs),
    (_, songs) => notifier.updateLikedSongs(songs),
  );
  ref.listen<bool>(
    floatingLyricsProvider.select((state) => state.enabled),
    (_, _) => notifier.refreshNotificationState(),
  );
  return notifier;
});
