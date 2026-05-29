import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/song.dart';
import '../../../../models/platform_type.dart';
import '../../../../platform/base/music_platform.dart';
import '../../../../platform/base/platform_registry.dart';

class PlaylistRecommendationsState {
  final Map<PlatformType, List<Song>> songsByPlatform;
  final Map<PlatformType, String> errorsByPlatform;
  final bool isLoading;
  final String? error;

  const PlaylistRecommendationsState({
    this.songsByPlatform = const {},
    this.errorsByPlatform = const {},
    this.isLoading = false,
    this.error,
  });

  PlaylistRecommendationsState copyWith({
    Map<PlatformType, List<Song>>? songsByPlatform,
    Map<PlatformType, String>? errorsByPlatform,
    bool? isLoading,
    String? Function()? error,
  }) {
    return PlaylistRecommendationsState(
      songsByPlatform: songsByPlatform ?? this.songsByPlatform,
      errorsByPlatform: errorsByPlatform ?? this.errorsByPlatform,
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
    );
  }

  List<Song> songsForPlatform(PlatformType platform) =>
      songsByPlatform[platform] ?? [];

  bool get hasData => songsByPlatform.isNotEmpty;

  int get totalCount =>
      songsByPlatform.values.fold(0, (sum, list) => sum + list.length);
}

class PlaylistRecommendationsNotifier
    extends StateNotifier<PlaylistRecommendationsState> {
  final List<PlatformType> Function() _supportedTypes;
  final MusicPlatform Function(PlatformType) _platformResolver;

  PlaylistRecommendationsNotifier({
    List<PlatformType>? supportedTypes,
    MusicPlatform Function(PlatformType)? platformResolver,
  })  : _supportedTypes =
            (() => supportedTypes ?? PlatformRegistry.supportedTypes),
        _platformResolver = platformResolver ?? PlatformRegistry.get,
        super(const PlaylistRecommendationsState());

  Future<void> loadRecommendations() async {
    state = state.copyWith(
      isLoading: true,
      error: () => null,
      errorsByPlatform: const {},
    );

    final results = <PlatformType, List<Song>>{};
    final errors = <PlatformType, String>{};
    var loggedInCount = 0;

    for (final platform in _supportedTypes()) {
      try {
        final platformImpl = _platformResolver(platform);
        if (!platformImpl.isLoggedIn) continue;

        loggedInCount++;
        final songs = await platformImpl.getDailyRecommendations();
        if (songs.isNotEmpty) {
          results[platform] = songs;
        }
      } catch (e) {
        errors[platform] = e.toString();
      }
    }

    String? nextError;
    if (loggedInCount == 0) {
      nextError = '请先登录平台账号';
    } else if (results.isEmpty) {
      nextError = errors.isNotEmpty ? '已登录平台推荐加载失败' : '暂无推荐内容';
    }

    state = state.copyWith(
      songsByPlatform: results,
      errorsByPlatform: errors,
      isLoading: false,
      error: () => nextError,
    );
  }
}

final playlistRecommendationsProvider = StateNotifierProvider<
    PlaylistRecommendationsNotifier, PlaylistRecommendationsState>((ref) {
  return PlaylistRecommendationsNotifier();
});
