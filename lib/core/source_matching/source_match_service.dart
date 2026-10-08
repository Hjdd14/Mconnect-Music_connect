import '../../models/audio_quality.dart';
import '../../models/platform_type.dart';
import '../../models/song.dart';
import '../../platform/base/music_platform.dart';
import '../../platform/base/platform_registry.dart';
import '../diagnostics/diagnostics_service.dart';
import 'source_match_cache.dart';
import 'track_identity.dart';

/// 可注入的内置平台列表（默认 [PlatformRegistry.all]）。
typedef SourceMatchPlatforms = List<MusicPlatform> Function();

/// 可注入的等待实现，让退避在用例里不真的 sleep。
typedef SourceMatchSleep = Future<void> Function(Duration duration);

/// 为什么没换成源（Wave 1-A）。
///
/// 分级只为"可判别的证据 + 诊断"，不改变失败链：链永远是
/// 「降一档音质 →（本服务）跨源换源 → skipToNext」。
enum SourceMatchFailure {
  /// 「自动换源」开关关掉了（设置页 D-2，默认开）。
  disabled,

  /// 离线模式：不许联网找源。
  offlineMode,

  /// 本地文件没有"另一个平台"可换。
  localSource,

  /// 另外两个内置平台都没给出候选（搜索为空/全被时长否决）。
  noCandidate,

  /// 有候选但分数没过阈值。
  belowThreshold,

  /// 候选找到了，但取不到可播直链。
  urlUnavailable,
}

/// 一次跨源解析的结果。
class SourceMatchResolution {
  SourceMatchResolution._({
    this.url,
    this.platform,
    this.targetSongId,
    this.score = 0,
    this.fromCache = false,
    this.failure,
  });

  factory SourceMatchResolution.resolved({
    required String url,
    required PlatformType platform,
    required String targetSongId,
    required double score,
    required bool fromCache,
  }) {
    return SourceMatchResolution._(
      url: url,
      platform: platform,
      targetSongId: targetSongId,
      score: score,
      fromCache: fromCache,
    );
  }

  factory SourceMatchResolution.failed(SourceMatchFailure failure) {
    return SourceMatchResolution._(failure: failure);
  }

  /// 可播直链；`null` 表示这次没换成源。
  final String? url;

  /// 直链来自哪个内置平台（播放页来源角标要用）。
  final PlatformType? platform;

  final String? targetSongId;
  final double score;

  /// 直链是缓存命中（未过期）还是这次真的重新解析过。
  final bool fromCache;

  final SourceMatchFailure? failure;

  bool get isResolved => url != null;
}

/// 跨源换源服务（Wave 1-A）——**只在内置三平台之间**，不接任何外部音源。
///
/// 一次 [resolveDetailed] 的顺序（每一步都写 DiagnosticsService）：
/// 1. 开关 / 离线 / 本地文件 → 直接放弃（不联网）；
/// 2. 逐个目标平台（另外两个内置平台里**已登录**的那些）先查缓存，命中且没过期
///    就直接用（`now + urlSafetyMargin` 之前到期的当作过期，见 [urlSafetyMargin]）；
/// 3. 没命中就搜索 → 打分（[scoreCandidate]）→ 过 [scoreThreshold] 才采用；
/// 4. 取流：先按请求档位，再逐级降档；成功才写缓存（带 [urlTtl]）。
///
/// 防风控：目标平台**串行**处理（同一时间只有一个平台在被请求），每个平台的搜索
/// 允许 [maxRetriesPerPlatform] 次指数退避重试，一次解析最多查
/// [maxPlatformsPerResolve] 个平台。任务描述里"并行查两个平台"与"串行 + 退避"冲突，
/// 这里优先**防风控**——换源只在失败链里被调用，慢一点换不到账号风险更重要。
class SourceMatchService {
  SourceMatchService({
    required this._cache,
    SourceMatchPlatforms? platforms,
    bool Function()? isAutoSwitchEnabled,
    bool Function()? isOfflineModeEnabled,
    DateTime Function()? now,
    SourceMatchSleep? sleep,
    this._diagnostics,
    this.scoreThreshold = 0.8,
    this.durationTolerance = const Duration(seconds: 3),
    this.urlTtl = const Duration(minutes: 20),
    this.urlSafetyMargin = const Duration(seconds: 60),
    this.searchLimit = 10,
    this.maxPlatformsPerResolve = 2,
    this.maxRetriesPerPlatform = 2,
    this.retryBaseDelay = const Duration(milliseconds: 300),
    this.requestTimeout = const Duration(seconds: 8),
  }) : _platforms = platforms ?? (() => PlatformRegistry.all),
       _isAutoSwitchEnabled = isAutoSwitchEnabled ?? (() => true),
       _isOfflineModeEnabled = isOfflineModeEnabled ?? (() => false),
       _now = now ?? DateTime.now,
       _sleep = sleep ?? ((duration) => Future<void>.delayed(duration));

  final SourceMatchCacheStore _cache;
  final SourceMatchPlatforms _platforms;
  final bool Function() _isAutoSwitchEnabled;
  final bool Function() _isOfflineModeEnabled;
  final DateTime Function() _now;
  final SourceMatchSleep _sleep;
  final DiagnosticsService? _diagnostics;

  /// 采用阈值（0.5×标题 + 0.3×主艺人 + 0.2×时长）。
  final double scoreThreshold;

  /// 时长容差：两侧时长都已知且差值超过它就**直接判不合格**（"时长不符不换"）。
  final Duration durationTolerance;

  /// 直链有效期：写缓存时的 `expiresAt`。
  final Duration urlTtl;

  /// 安全余量：解析时把 `now` 往后挪这个量再查缓存，于是"马上要过期的签名直链"
  /// 会被当作过期重新解析（命中缓存 ≠ 可直接播）。
  final Duration urlSafetyMargin;

  final int searchLimit;
  final int maxPlatformsPerResolve;
  final int maxRetriesPerPlatform;
  final Duration retryBaseDelay;
  final Duration requestTimeout;

  DiagnosticsService get _diag =>
      _diagnostics ?? DiagnosticsService.instance;

  /// W0-A 的 `crossSourceResolver` 形状：只要直链。
  Future<String?> resolve(Song song, AudioLevel quality) async {
    final resolution = await resolveDetailed(song, quality);
    return resolution.url;
  }

  /// 播放失败后立刻作废该 `(歌曲, 目标平台)` 的缓存（W2-B / 复核 F3）。
  ///
  /// 调用方（player 的换源失败路径）只知道"这条换源直链放不出来"，所以这里只失效
  /// + 记诊断，不重解析；下一次失败链自然会重新走 [resolveDetailed]。不这么做的话，
  /// 一条"时间上还有效、服务端已失效"的直链会被复用满整个 TTL（20 分钟）。
  Future<void> invalidateCache(Song song, PlatformType targetPlatform) async {
    final songKey = song.dedupeKey;
    try {
      await _cache.invalidate(songKey, targetPlatform.name);
      _diag.record(
        'source_match',
        'source_match_cache_invalidated',
        data: {'song_id': song.id, 'platform': targetPlatform.name},
      );
    } catch (error, stack) {
      _diag.recordError(
        'source_match.cacheInvalidate',
        error,
        stack,
        data: {'song_key': songKey, 'platform': targetPlatform.name},
      );
    }
  }

  Future<SourceMatchResolution> resolveDetailed(
    Song song,
    AudioLevel quality,
  ) async {
    if (!_isAutoSwitchEnabled()) {
      return SourceMatchResolution.failed(SourceMatchFailure.disabled);
    }
    if (_isOfflineModeEnabled()) {
      return SourceMatchResolution.failed(SourceMatchFailure.offlineMode);
    }
    if (song.platform == PlatformType.local) {
      return SourceMatchResolution.failed(SourceMatchFailure.localSource);
    }

    final identity = TrackIdentity.fromSong(song);
    final songKey = song.dedupeKey;
    var platformsQueried = 0;
    var bestScoreSeen = 0.0;
    var sawCandidate = false;
    // 「过了阈值的候选」与「搜到过的候选」必须分开记：只用一个 bool 时
    // `SourceMatchFailure.belowThreshold` 不可达（复核 F1），"有候选但时长差 >3s
    // 得 0 分"会被误报成 urlUnavailable。
    var passedThreshold = false;

    for (final platform in _targetPlatforms(song)) {
      final target = platform.platformType.name;

      final cached = await _readCache(songKey, target);
      final cachedUrl = cached?.url;
      if (cached != null && cachedUrl != null) {
        _diag.record(
          'source_match',
          'source_match_cache_hit',
          data: {
            'song_id': song.id,
            'platform': target,
            'target_song_id': cached.targetSongId,
            'score': cached.score,
          },
        );
        return SourceMatchResolution.resolved(
          url: cachedUrl,
          platform: platform.platformType,
          targetSongId: cached.targetSongId,
          score: cached.score,
          fromCache: true,
        );
      }

      if (platformsQueried >= maxPlatformsPerResolve) break;
      platformsQueried++;

      final results = await _searchWithRetry(platform, song);
      final best = _bestCandidate(identity, results);
      if (best != null) {
        sawCandidate = true;
        if (best.score > bestScoreSeen) bestScoreSeen = best.score;
      }
      if (best == null || best.score < scoreThreshold) {
        _diag.record(
          'source_match',
          'source_match_rejected',
          data: {
            'song_id': song.id,
            'platform': target,
            'candidates': results.length,
            'best_score': best?.score ?? 0,
            'threshold': scoreThreshold,
          },
        );
        continue;
      }

      // 走到这里 = 候选过了阈值（可能后面仍旧取不到直链）。
      passedThreshold = true;

      final url = await _fetchUrl(platform, best.song, quality);
      if (url == null) {
        _diag.record(
          'source_match',
          'source_match_url_unavailable',
          data: {
            'song_id': song.id,
            'platform': target,
            'target_song_id': best.song.id,
          },
        );
        continue;
      }

      final fetchedAt = _now();
      await _writeCache(
        SourceMatchEntry(
          songKey: songKey,
          targetPlatform: target,
          targetSongId: best.song.id,
          url: url,
          urlFetchedAt: fetchedAt,
          score: best.score,
          expiresAt: fetchedAt.add(urlTtl),
        ),
      );
      _diag.record(
        'source_match',
        'source_match_hit',
        data: {
          'song_id': song.id,
          'platform': target,
          'target_song_id': best.song.id,
          'score': best.score,
          'quality': quality.name,
        },
      );
      return SourceMatchResolution.resolved(
        url: url,
        platform: platform.platformType,
        targetSongId: best.song.id,
        score: best.score,
        fromCache: false,
      );
    }

    _diag.record(
      'source_match',
      'source_match_failed',
      data: {
        'song_id': song.id,
        'platform': song.platform.name,
        // 键名与值必须同型：以前这里是 `'candidates_seen': sawCandidate`，
        // 键像计数、值是 bool，诊断消费者会误读（复核 F1 顺带项）。
        'candidate_found': sawCandidate,
        'passed_threshold': passedThreshold,
        'best_score': bestScoreSeen,
      },
    );
    return SourceMatchResolution.failed(
      passedThreshold
          // 过了阈值却没拿到直链：取流失败。
          ? SourceMatchFailure.urlUnavailable
          : (sawCandidate
                // 搜到了候选但全不及格（含"时长差 >3s → 0 分"）。
                ? SourceMatchFailure.belowThreshold
                : SourceMatchFailure.noCandidate),
    );
  }

  /// 打分：标题 0.5 / 主艺人 0.3 / 时长 0.2。
  ///
  /// * 时长：两侧都已知且差值 > [durationTolerance] → **0 分**（不合格）；
  /// * 主艺人：任一侧为空时给 0.5 中性分（各平台对"空艺人"的表示不同，
  ///   直接给 0 会把正常匹配压到阈值以下）；
  /// * 文本：完全相同 1.0，互为子串 0.7，否则 0。
  double scoreCandidate(TrackIdentity identity, Song candidate) {
    final other = TrackIdentity.fromSong(candidate);
    final hasDuration =
        identity.duration > Duration.zero && other.duration > Duration.zero;
    if (hasDuration) {
      final delta = (identity.duration - other.duration).abs();
      if (delta > durationTolerance) return 0;
    }

    final title = _textScore(identity.titleKey, other.titleKey);
    final artist = identity.artistKey.isEmpty || other.artistKey.isEmpty
        ? 0.5
        : _textScore(identity.artistKey, other.artistKey);
    final duration = hasDuration
        ? 1 -
              ((identity.duration - other.duration).abs().inMilliseconds /
                  durationTolerance.inMilliseconds)
        : 0.5;

    return (title * 0.5 + artist * 0.3 + duration * 0.2)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  static double _textScore(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    if (a.contains(b) || b.contains(a)) return 0.7;
    return 0;
  }

  /// 另外两个内置平台里**已登录**的那些（未登录的平台必然取不到流，别浪费请求）。
  List<MusicPlatform> _targetPlatforms(Song song) {
    return [
      for (final platform in _platforms())
        if (platform.platformType != song.platform &&
            platform.platformType != PlatformType.local &&
            platform.isLoggedIn)
          platform,
    ];
  }

  ({Song song, double score})? _bestCandidate(
    TrackIdentity identity,
    List<Song> candidates,
  ) {
    ({Song song, double score})? best;
    for (final candidate in candidates) {
      final score = scoreCandidate(identity, candidate);
      if (best == null || score > best.score) {
        best = (song: candidate, score: score);
      }
    }
    return best;
  }

  Future<List<Song>> _searchWithRetry(
    MusicPlatform platform,
    Song song,
  ) async {
    for (var attempt = 0; attempt <= maxRetriesPerPlatform; attempt++) {
      try {
        return await platform.search(song.name, limit: searchLimit);
      } catch (error, stack) {
        _diag.recordError(
          'source_match.search',
          error,
          stack,
          data: {
            'platform': platform.platformType.name,
            'song_id': song.id,
            'attempt': attempt,
          },
        );
        if (attempt == maxRetriesPerPlatform) return const <Song>[];
        // 指数退避：0.3s → 0.6s → ...
        await _sleep(retryBaseDelay * (1 << attempt));
      }
    }
    return const <Song>[];
  }

  /// 取流：先按请求档位，再逐级降档（换源方的"音质达标"就是这么判的）。
  Future<String?> _fetchUrl(
    MusicPlatform platform,
    Song candidate,
    AudioLevel quality,
  ) async {
    for (final level in _qualityOrder(quality)) {
      try {
        final url = await platform
            .getSongUrl(candidate.id, quality: level)
            .timeout(requestTimeout);
        if (url.trim().isNotEmpty) return url;
      } catch (error, stack) {
        _diag.recordError(
          'source_match.getSongUrl',
          error,
          stack,
          data: {
            'platform': platform.platformType.name,
            'song_id': candidate.id,
            'quality': level.name,
          },
        );
      }
    }
    return null;
  }

  static List<AudioLevel> _qualityOrder(AudioLevel quality) {
    final levels = <AudioLevel>[quality];
    final lower = [
      for (final level in AudioLevel.values)
        if (level.index < quality.index) level,
    ];
    for (final level in lower.reversed) {
      levels.add(level);
    }
    return levels;
  }

  Future<SourceMatchEntry?> _readCache(
    String songKey,
    String targetPlatform,
  ) async {
    try {
      final cached = await _cache.get(
        songKey,
        targetPlatform,
        // 安全余量：把 now 往后挪，于是"余量内就要过期"的直链被当成过期重解析。
        now: _now().add(urlSafetyMargin),
      );
      // 纵深防御（复核 F2）：TTL 的正确性目前**完全**押在"每个 store 实现都遵守
      // get(now:) 契约"上。这里再用 isUsableAt 复核一次，代价是一次比较：任何
      // store 实现违约（忘了判过期）都不会把死链放进播放。
      if (cached != null && !cached.isUsableAt(_now())) return null;
      return cached;
    } catch (error, stack) {
      _diag.recordError(
        'source_match.cacheGet',
        error,
        stack,
        data: {'song_key': songKey, 'platform': targetPlatform},
      );
      return null;
    }
  }

  Future<void> _writeCache(SourceMatchEntry entry) async {
    try {
      await _cache.put(entry);
    } catch (error, stack) {
      _diag.recordError(
        'source_match.cachePut',
        error,
        stack,
        data: {'song_key': entry.songKey, 'platform': entry.targetPlatform},
      );
    }
  }
}
