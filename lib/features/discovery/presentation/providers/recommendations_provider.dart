import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/recommendation_source.dart';
import '../../../../models/song.dart';
import '../../../../models/platform_type.dart';
import '../../../../platform/base/music_platform.dart';
import '../../../../platform/base/platform_registry.dart';

/// Daily recommendations, one entry per platform that advertises support.
///
/// This used to be driven by a hardcoded constant
/// (`verifiedDailyRecommendationPlatforms = [netease]`), which is why QQ音乐
/// and 酷狗 never appeared even though both adapters implement
/// `getDailyRecommendations()`. It is now driven by
/// [MusicPlatform.supportsDailyRecommendations], and each platform reports
/// **where its list came from** ([RecommendationSource]) because the three
/// platforms cannot make the same promise:
///
/// * 网易云 — genuinely personalised daily playlist;
/// * QQ音乐 — personalised 「今日私享」 only while logged in, otherwise a chart;
/// * 酷狗 — its official recommendation endpoints are refused server-side, so
///   the list comes from the mobile homepage module.
///
/// The UI is expected to render the source badge so "酷狗推荐" is never
/// presented as "每日推荐".
class RecommendationsState {
  final Map<PlatformType, List<Song>> songsByPlatform;
  final Map<PlatformType, String> errorsByPlatform;
  final Map<PlatformType, RecommendationSource> sourceByPlatform;
  final bool isLoading;
  final String? error;

  const RecommendationsState({
    this.songsByPlatform = const {},
    this.errorsByPlatform = const {},
    this.sourceByPlatform = const {},
    this.isLoading = false,
    this.error,
  });

  RecommendationsState copyWith({
    Map<PlatformType, List<Song>>? songsByPlatform,
    Map<PlatformType, String>? errorsByPlatform,
    Map<PlatformType, RecommendationSource>? sourceByPlatform,
    bool? isLoading,
    String? Function()? error,
  }) {
    return RecommendationsState(
      songsByPlatform: songsByPlatform ?? this.songsByPlatform,
      errorsByPlatform: errorsByPlatform ?? this.errorsByPlatform,
      sourceByPlatform: sourceByPlatform ?? this.sourceByPlatform,
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
    );
  }

  List<Song> songsForPlatform(PlatformType platform) =>
      songsByPlatform[platform] ?? [];

  RecommendationSource? sourceForPlatform(PlatformType platform) =>
      sourceByPlatform[platform];

  int get totalCount =>
      songsByPlatform.values.fold(0, (sum, list) => sum + list.length);
}

class RecommendationsNotifier extends StateNotifier<RecommendationsState> {
  final List<PlatformType> Function() _supportedTypes;
  final MusicPlatform Function(PlatformType) _platformResolver;
  final Duration _operationTimeout;

  RecommendationsNotifier({
    List<PlatformType>? supportedTypes,
    MusicPlatform Function(PlatformType)? platformResolver,
    this._operationTimeout = const Duration(seconds: 12),
  }) : _supportedTypes = (() =>
           supportedTypes ?? PlatformRegistry.supportedTypes),
       _platformResolver = platformResolver ?? PlatformRegistry.get,
       super(const RecommendationsState());

  Future<void> loadRecommendations() async {
    state = state.copyWith(
      isLoading: true,
      error: () => null,
      errorsByPlatform: const {},
      sourceByPlatform: const {},
    );

    final supported = <PlatformType>[];
    for (final platform in _supportedTypes()) {
      MusicPlatform? impl;
      try {
        impl = _platformResolver(platform);
      } catch (_) {
        impl = null;
      }
      // A platform that does not advertise the capability is not queried at
      // all, so its absence is not reported as an error.
      if (impl != null && impl.supportsDailyRecommendations) {
        supported.add(platform);
      }
    }

    final loaded = await Future.wait(
      supported.map(_loadPlatformRecommendations),
    );
    if (!mounted) return;

    final results = <PlatformType, List<Song>>{};
    final errors = <PlatformType, String>{};
    final sources = <PlatformType, RecommendationSource>{};
    var loggedInCount = 0;

    for (final item in loaded) {
      if (item.loggedIn) loggedInCount++;
      final source = item.source;
      if (source != null) sources[item.platform] = source;
      // A logged-in platform stays visible even with zero songs, so the page
      // can explain "logged in but nothing to show" instead of hiding it.
      if (item.songs.isNotEmpty || item.loggedIn) {
        results[item.platform] = item.songs;
      }
      final error = item.error;
      if (error != null) errors[item.platform] = error;
    }

    // Only blame login when nothing at all could be produced. A single
    // platform failing must not turn into a page-level error.
    final String? nextError =
        results.isEmpty && loggedInCount == 0 ? '请先登录平台账号' : null;

    state = state.copyWith(
      songsByPlatform: results,
      errorsByPlatform: errors,
      sourceByPlatform: sources,
      isLoading: false,
      error: () => nextError,
    );
  }

  Future<_RecommendationLoadResult> _loadPlatformRecommendations(
    PlatformType platform,
  ) async {
    MusicPlatform? platformImpl;
    var loggedIn = false;
    try {
      platformImpl = _platformResolver(platform);
      loggedIn = platformImpl.isLoggedIn;

      final result = await platformImpl
          .getDailyRecommendation()
          .timeout(_operationTimeout);
      return _RecommendationLoadResult(
        platform: platform,
        loggedIn: loggedIn,
        songs: result.songs,
        source: result.source,
        error: result.error,
      );
    } on TimeoutException {
      return _RecommendationLoadResult(
        platform: platform,
        loggedIn: loggedIn || platformImpl?.isLoggedIn == true,
        error: 'timeout',
        source: _unavailable(platform, '请求超时'),
      );
    } catch (e) {
      return _RecommendationLoadResult(
        platform: platform,
        loggedIn: loggedIn || platformImpl?.isLoggedIn == true,
        error: e.toString(),
        source: _unavailable(platform, '加载失败'),
      );
    }
  }

  RecommendationSource _unavailable(PlatformType platform, String note) {
    return RecommendationSource(
      platform: platform,
      kind: RecommendationKind.unavailable,
      label: '不可用',
      note: note,
    );
  }
}

class _RecommendationLoadResult {
  final PlatformType platform;
  final bool loggedIn;
  final List<Song> songs;
  final RecommendationSource? source;
  final String? error;

  const _RecommendationLoadResult({
    required this.platform,
    this.loggedIn = false,
    this.songs = const [],
    this.source,
    this.error,
  });
}

final recommendationsProvider =
    StateNotifierProvider<RecommendationsNotifier, RecommendationsState>((ref) {
      return RecommendationsNotifier();
    });
