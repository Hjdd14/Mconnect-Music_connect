import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/song.dart';
import '../../../../models/platform_type.dart';
import '../../../../platform/base/music_platform.dart';
import '../../../../platform/base/platform_registry.dart';

const verifiedDailyRecommendationPlatforms = <PlatformType>[
  PlatformType.netease,
];

class RecommendationsState {
  final Map<PlatformType, List<Song>> songsByPlatform;
  final Map<PlatformType, String> errorsByPlatform;
  final bool isLoading;
  final String? error;

  const RecommendationsState({
    this.songsByPlatform = const {},
    this.errorsByPlatform = const {},
    this.isLoading = false,
    this.error,
  });

  RecommendationsState copyWith({
    Map<PlatformType, List<Song>>? songsByPlatform,
    Map<PlatformType, String>? errorsByPlatform,
    bool? isLoading,
    String? Function()? error,
  }) {
    return RecommendationsState(
      songsByPlatform: songsByPlatform ?? this.songsByPlatform,
      errorsByPlatform: errorsByPlatform ?? this.errorsByPlatform,
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
    );
  }

  List<Song> songsForPlatform(PlatformType platform) =>
      songsByPlatform[platform] ?? [];

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
    Duration operationTimeout = const Duration(seconds: 12),
  }) : _supportedTypes = (() =>
           supportedTypes ?? PlatformRegistry.supportedTypes),
       _platformResolver = platformResolver ?? PlatformRegistry.get,
       _operationTimeout = operationTimeout,
       super(const RecommendationsState());

  Future<void> loadRecommendations() async {
    state = state.copyWith(
      isLoading: true,
      error: () => null,
      errorsByPlatform: const {},
    );

    final platforms = _supportedTypes()
        .where(verifiedDailyRecommendationPlatforms.contains)
        .toList(growable: false);
    final loaded = await Future.wait(
      platforms.map(_loadPlatformRecommendations),
    );
    if (!mounted) return;
    final results = <PlatformType, List<Song>>{};
    final errors = <PlatformType, String>{};
    var loggedInCount = 0;

    for (final item in loaded) {
      if (item.loggedIn) {
        loggedInCount++;
        results[item.platform] = item.songs;
      }
      final error = item.error;
      if (error != null) errors[item.platform] = error;
    }

    String? nextError;
    if (loggedInCount == 0) {
      nextError = '请先登录平台账号';
    }

    state = state.copyWith(
      songsByPlatform: results,
      errorsByPlatform: errors,
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
      if (!loggedIn) {
        return _RecommendationLoadResult(platform: platform);
      }

      final songs = await platformImpl.getDailyRecommendations().timeout(
        _operationTimeout,
      );
      return _RecommendationLoadResult(
        platform: platform,
        loggedIn: true,
        songs: songs,
      );
    } on TimeoutException {
      return _RecommendationLoadResult(
        platform: platform,
        loggedIn: loggedIn || platformImpl?.isLoggedIn == true,
        error: 'timeout',
      );
    } catch (e) {
      return _RecommendationLoadResult(
        platform: platform,
        loggedIn: loggedIn || platformImpl?.isLoggedIn == true,
        error: e.toString(),
      );
    }
  }
}

class _RecommendationLoadResult {
  final PlatformType platform;
  final bool loggedIn;
  final List<Song> songs;
  final String? error;

  const _RecommendationLoadResult({
    required this.platform,
    this.loggedIn = false,
    this.songs = const [],
    this.error,
  });
}

final recommendationsProvider =
    StateNotifierProvider<RecommendationsNotifier, RecommendationsState>((ref) {
      return RecommendationsNotifier();
    });
