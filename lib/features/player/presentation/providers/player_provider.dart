import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' show AudioPlayer, ProcessingState;
import '../../../../core/database/app_database.dart';
import '../../../../core/diagnostics/diagnostics_service.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/platform_http.dart';
import '../../../../core/source_matching/drift_source_match_cache_store.dart';
import '../../../../core/source_matching/source_match_service.dart';
import '../../../../core/source_matching/source_match_settings.dart';
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
import '../../data/next_track_prefetcher.dart';
import '../../data/player_audio_controller.dart';
import '../../data/player_playback_memory_store.dart';
import '../../data/playback_keep_alive_service.dart';
import '../../data/playback_notification_service.dart' as playback_notification;

export '../../data/player_audio_controller.dart';

// ── Wave 1-A 拆分地图（part 而不是模块边界） ───────────────────────────────
// 4 个 part 与本文件**同一个库**：它们共享下面 PlayerNotifier 的每个私有字段，
// 所以这是"行为搬出去、状态留在 facade"，不是可独立复用的模块。
//   data/playback_health_monitor.dart      健康监测 + 卡死看门狗 + 停滞自愈 + 音量守护 + _AudioMutex
//   data/playback_fade_controller.dart     淡入淡出 + 音量 + 播放选项（倍速/跳过静音/A-B）
//   data/playback_memory_coordinator.dart  断点续播 + A-2 播放偏好落盘
//   data/notification_state_sync.dart      通知/MediaSession 与「喜欢」状态同步
// NOTE the `../../`: this file lives in presentation/providers/, so `..` alone
// would resolve to presentation/data/ — the parts are in features/player/data/.
part '../../data/playback_health_monitor.dart';
part '../../data/playback_fade_controller.dart';
part '../../data/playback_memory_coordinator.dart';
part '../../data/notification_state_sync.dart';

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
    Future<CrossSourceResult?> Function(Song song, AudioLevel quality);

/// 一次跨源换源的结果（Wave 1-A）。
///
/// 失败链只要 URL，但播放页的「已换源 · 来自 X」角标需要**来源平台**——两者是同一次
/// 解析的产物，所以一起返回，而不是让调用方再反查一次。
class CrossSourceResult {
  const CrossSourceResult({
    required this.url,
    this.platform,
    this.fromCache = false,
  });

  final String url;

  /// 直链来自哪个内置平台（角标用）。
  final PlatformType? platform;

  /// 直链是缓存命中（未过期）还是本轮重新解析。
  final bool fromCache;
}

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

  /// 当前音频**实际来自哪个平台**（Wave 1-A 跨源换源）。
  ///
  /// `null` = 就是 [currentSong] 自己的平台（正常播放）；非 null 且与
  /// `currentSong.platform` 不同时，播放页显示「已换源 · 来自 X」角标。
  final PlatformType? sourcePlatform;

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
    this.sourcePlatform,
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
    PlatformType? Function()? sourcePlatform,
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
      sourcePlatform: sourcePlatform != null
          ? sourcePlatform()
          : this.sourcePlatform,
    );
  }

  /// 值相等（Wave 1-A）。
  ///
  /// `StateNotifier` 只在 `nextState != state` 时通知。没有 `==` 时**任何**调用都会
  /// 换一个新实例 → 所有监听者（含只关心 `isShuffle` 的按钮、只关心 `currentSong`
  /// 的 mini player）被唤醒；`player_audio_controller` 重复上报同一个
  /// playing/processingState 时也会白唤一轮。有了 `==`，内容没变的更新被吸收。
  ///
  /// **`position` 必须参与比较**：位置每秒推进是真的状态变化，进度条/胶囊进度环
  /// 依赖它触发重绘。把它排除掉会静默吃掉所有播放进度更新（早先 W0-A 的
  /// "播放页进度不动"就是这个形态）。
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlayerState &&
        other.currentSong?.id == currentSong?.id &&
        other.currentSong?.platform == currentSong?.platform &&
        other.currentIndex == currentIndex &&
        other.isPlaying == isPlaying &&
        other.position == position &&
        other.duration == duration &&
        other.currentQuality == currentQuality &&
        other.qualityPreference == qualityPreference &&
        other.error == error &&
        other.isShuffle == isShuffle &&
        other.repeatMode == repeatMode &&
        other.isTransitioning == isTransitioning &&
        other.playbackSpeed == playbackSpeed &&
        other.skipSilence == skipSilence &&
        other.abLoopStart == abLoopStart &&
        other.abLoopEnd == abLoopEnd &&
        other.sourcePlatform == sourcePlatform;
  }

  @override
  int get hashCode => Object.hash(
    currentSong?.id,
    currentSong?.platform,
    currentIndex,
    isPlaying,
    position,
    duration,
    currentQuality,
    qualityPreference,
    error,
    isShuffle,
    repeatMode,
    isTransitioning,
    playbackSpeed,
    skipSilence,
    abLoopStart,
    abLoopEnd,
    sourcePlatform,
  );
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

  /// 下一首预解析（Wave 1-A 步骤 3）；`null` 时不做任何预取。
  final NextTrackPrefetcher? _prefetcher;

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

  /// 上一次已排入预解析的 `(playlist, index, quality)` key（Wave 1-A 步骤 3）。
  String? _lastPrefetchKey;

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
    this._prefetcher,
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
    _maybeScheduleNextTrackPrefetch(nextState);
  }

  /// 队列/下标/音质真的变了才重新预解析（Wave 1-A 步骤 3）。
  ///
  /// `_setState` 每秒都会被位置 tick 走到，所以这里必须便宜且**幂等**：用
  /// `(playlist 实例, 下标, 档位)` 组成 key，位置 tick 不会改变它们 → 直接返回。
  void _maybeScheduleNextTrackPrefetch(PlayerState nextState) {
    final prefetcher = _prefetcher;
    if (prefetcher == null) return;
    final key =
        '${identityHashCode(nextState.playlist)}'
        ':${nextState.currentIndex}'
        ':${nextState.currentQuality.name}';
    if (key == _lastPrefetchKey) return;
    _lastPrefetchKey = key;
    if (nextState.currentSong == null) {
      prefetcher.cancel();
      return;
    }
    prefetcher.schedule(
      playlist: nextState.playlist,
      currentIndex: nextState.currentIndex,
      quality: nextState.currentQuality,
    );
  }

  /// Records that the transport did something observable.
  ///
  /// The stuck watchdog (see [_checkStuckTransport]) only fires when *nothing*
  /// has progressed for [_stuckWatchdogThreshold], so every real state change —
  /// position, processing state, request generation, flags — has to rearm it.
  void _markTransportProgress() {
    _lastTransportProgressAt = _now();
  }

  /// `(platform, id)` 形式的喜欢键。
  ///
  /// 与 `likes_provider.dart` 里 `'${platform}_${id}'` 的拼法同构，也与本文件的
  /// [_songKey] 同义。用 id+platform 而不是 `Song.dedupeKey`：喜欢列表是按
  /// `(id, platform)` 存的（见 `LikesNotifier.toggleLike`），用 dedupeKey 会把
  /// 同一首歌在另一个平台上的条目也判成"已喜欢"。
  /// Reads [state] for the code that lives in the `part` files.
  ///
  /// `StateNotifier.state` is annotated `@protected` **and**
  /// `@visibleForTesting`, and the analyzer enforces both: an `extension` on
  /// `PlayerNotifier` is not an instance member of the subclass, so touching
  /// `state` from a part produces two warnings per access
  /// (`invalid_use_of_protected_member` +
  /// `invalid_use_of_visible_for_testing_member`) — 98 accesses meant ~196
  /// warnings, i.e. the repository's "analyze: 0 issues" gate could never pass.
  ///
  /// A getter *declared in the class* is a plain instance member, so parts may
  /// read it through the implicit `this`. This exists solely for that reason;
  /// do not add new state mutations here (writes stay in the facade).
  PlayerState get _s => state;

  static String likedSongKeyFor(Song song) =>
      '${song.platform.name}_${song.id}';

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

  AudioPlayer get audioPlayer {
    final controller = _ensureAudioController();
    if (controller is JustAudioController) {
      return controller.player;
    }
    throw StateError(
      'The injected audio controller does not expose just_audio.AudioPlayer.',
    );
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
              // 新的一首可能又要换源：先把上一首的来源角标清掉（Wave 1-A）。
              sourcePlatform: () => null,
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
              sourcePlatform: () => null,
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
        final result = await resolver(failure.song, quality);
        if (!mounted || failure.requestId != _playRequestId) return false;
        final url = result?.url;
        if (url == null || url.trim().isEmpty) continue;
        if (await _playResolvedUrl(
          failure,
          url,
          quality,
          'crossSource',
          // 角标要的"来自哪个平台"就来自这次解析的结果（Wave 1-A）。
          sourcePlatform: result?.platform,
        )) {
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
  ///
  /// [sourcePlatform] 只在"跨源换源"这条路上非空：它决定播放页的来源角标；降档
  /// 重试仍然是原平台，传 `null`（= 清掉旧角标）。
  Future<bool> _playResolvedUrl(
    _PlaybackFailure failure,
    String url,
    AudioLevel quality,
    String label, {
    PlatformType? sourcePlatform,
  }) {
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
            sourcePlatform: () => sourcePlatform,
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
  // Wave 1-A 跨源换源的装配点。
  //
  // * 只在内置三平台之间找源（服务内部从 PlatformRegistry.all 里排除主平台与
  //   local，并要求 isLoggedIn）；
  // * 「自动换源」开关（设置页 D-2，默认开）与离线模式在这里注入：关掉开关或
  //   离线时 resolveDetailed 直接返回 disabled/offlineMode，失败链退化为
  //   「降档 → skipToNext」；
  // * 缓存用 W0-D 的 SourceMatchCache（DAO 惰性取，装配时不碰数据库）。
  final sourceMatchService = SourceMatchService(
    cache: DriftSourceMatchCacheStore(() => database.sourceMatchCacheDao),
    isAutoSwitchEnabled: () => ref.read(autoSourceSwitchProvider).enabled,
    isOfflineModeEnabled: () =>
        ref.read(offlineCacheSettingsProvider).offlineMode,
  );
  final prefetcher = NextTrackPrefetcher(
    service: sourceMatchService,
    isOfflineModeEnabled: () =>
        ref.read(offlineCacheSettingsProvider).offlineMode,
  );
  final notifier = PlayerNotifier(
    playbackMemoryStore: HivePlayerPlaybackMemoryStore(),
    prefetcher: prefetcher,
    crossSourceResolver: (song, quality) async {
      final resolution = await sourceMatchService.resolveDetailed(
        song,
        quality,
      );
      final url = resolution.url;
      if (url == null) return null;
      return CrossSourceResult(
        url: url,
        platform: resolution.platform,
        fromCache: resolution.fromCache,
      );
    },
    // P-1：喜欢状态不再走"每秒问一遍 likesProvider.songs.any(...)"的回调（最多
    // 500 首 × 每秒一次，Windows 也一样），改成下面 seed + 增量推送 key 集合。
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
