import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/song.dart';
import '../../../../models/platform_type.dart';
import '../../../../platform/base/music_platform.dart';
import '../../../../platform/base/platform_registry.dart';

/// 排行榜 (the legacy flat "hot songs per platform" view).
///
/// Two defects used to hide QQ here, and both are fixed in this state:
/// * the empty `catch` swallowed every platform failure without a trace, and
/// * `if (songs.isNotEmpty)` **dropped** a platform that produced no songs, so a
///   failing QQ simply vanished from the tabs instead of saying why — half of the
///   reported "QQ 热歌榜没有入口". Failures now land in [errorsByPlatform] and
///   the platform keeps its tab.
class RankingsState {
  final Map<PlatformType, List<Song>> songsByPlatform;
  final Map<PlatformType, String> errorsByPlatform;
  final bool isLoading;
  final String? error;

  const RankingsState({
    this.songsByPlatform = const {},
    this.errorsByPlatform = const {},
    this.isLoading = false,
    this.error,
  });

  RankingsState copyWith({
    Map<PlatformType, List<Song>>? songsByPlatform,
    Map<PlatformType, String>? errorsByPlatform,
    bool? isLoading,
    String? Function()? error,
  }) {
    return RankingsState(
      songsByPlatform: songsByPlatform ?? this.songsByPlatform,
      errorsByPlatform: errorsByPlatform ?? this.errorsByPlatform,
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
    );
  }

  List<Song> songsForPlatform(PlatformType platform) =>
      songsByPlatform[platform] ?? [];

  String? errorForPlatform(PlatformType platform) =>
      errorsByPlatform[platform];

  /// Platforms that either produced songs or failed — i.e. every platform the
  /// page must show a tab for.
  List<PlatformType> get visiblePlatforms {
    final platforms = <PlatformType>{...songsByPlatform.keys};
    platforms.addAll(errorsByPlatform.keys);
    return PlatformType.musicServices
        .where(platforms.contains)
        .toList();
  }

  int get totalCount =>
      songsByPlatform.values.fold(0, (sum, list) => sum + list.length);
}

class RankingsNotifier extends StateNotifier<RankingsState> {
  final List<PlatformType> Function() _supportedTypes;
  final MusicPlatform Function(PlatformType) _platformResolver;
  final Duration operationTimeout;

  RankingsNotifier({
    List<PlatformType>? supportedTypes,
    MusicPlatform Function(PlatformType)? platformResolver,
    this.operationTimeout = const Duration(seconds: 12),
  }) : _supportedTypes = (() =>
           supportedTypes ?? PlatformRegistry.supportedTypes),
       _platformResolver = platformResolver ?? PlatformRegistry.get,
       super(const RankingsState());

  Future<void> loadRankings() async {
    state = state.copyWith(
      isLoading: true,
      error: () => null,
      errorsByPlatform: const {},
    );

    // Each platform is resolved exactly once: resolving twice (a capability
    // probe followed by a load) made tests unable to count the queries and made
    // a resolver side effect run twice in production.
    final implementations = _implementations();

    final loaded = await Future.wait(implementations.map(_loadPlatform));
    if (!mounted) return;

    final songs = <PlatformType, List<Song>>{};
    final errors = <PlatformType, String>{};
    for (final item in loaded) {
      final error = item.error;
      if (error != null) errors[item.platform] = error;
      // Every queried platform is kept: a platform with no songs and no error
      // still gets a tab, which then says "no chart data" instead of vanishing
      // (the old code dropped it, which is how QQ disappeared from the tabs).
      songs[item.platform] = item.songs;
    }

    state = state.copyWith(
      songsByPlatform: songs,
      errorsByPlatform: errors,
      isLoading: false,
      error: () =>
          songs.values.every((list) => list.isEmpty) && errors.isEmpty
          ? '暂无排行榜数据'
          : null,
    );
  }

  Future<_PlatformRanking> _loadPlatform(MusicPlatform impl) async {
    final platform = impl.platformType;
    try {
      final songs = await impl.getRankingList().timeout(operationTimeout);
      return _PlatformRanking(platform: platform, songs: songs);
    } on TimeoutException {
      return _PlatformRanking(platform: platform, error: '请求超时');
    } catch (e) {
      return _PlatformRanking(platform: platform, error: '$e');
    }
  }
  /// Resolves every music-service platform this notifier should query.
  List<MusicPlatform> _implementations() {
    final implementations = <MusicPlatform>[];
    for (final type in _supportedTypes()) {
      if (!type.isMusicService) continue;
      try {
        implementations.add(_platformResolver(type));
      } catch (_) {
        // A platform that is registered but not constructible is skipped
        // instead of breaking the whole page.
      }
    }
    return implementations;
  }
}

class _PlatformRanking {
  final PlatformType platform;
  final List<Song> songs;
  final String? error;

  const _PlatformRanking({
    required this.platform,
    this.songs = const [],
    this.error,
  });
}

final rankingsProvider =
    StateNotifierProvider<RankingsNotifier, RankingsState>((ref) {
  return RankingsNotifier();
});
