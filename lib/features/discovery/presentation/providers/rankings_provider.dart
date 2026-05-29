import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/song.dart';
import '../../../../models/platform_type.dart';
import '../../../../platform/base/platform_registry.dart';

class RankingsState {
  final Map<PlatformType, List<Song>> songsByPlatform;
  final bool isLoading;
  final String? error;

  const RankingsState({
    this.songsByPlatform = const {},
    this.isLoading = false,
    this.error,
  });

  RankingsState copyWith({
    Map<PlatformType, List<Song>>? songsByPlatform,
    bool? isLoading,
    String? Function()? error,
  }) {
    return RankingsState(
      songsByPlatform: songsByPlatform ?? this.songsByPlatform,
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
    );
  }

  List<Song> songsForPlatform(PlatformType platform) =>
      songsByPlatform[platform] ?? [];

  int get totalCount =>
      songsByPlatform.values.fold(0, (sum, list) => sum + list.length);
}

class RankingsNotifier extends StateNotifier<RankingsState> {
  RankingsNotifier() : super(const RankingsState());

  Future<void> loadRankings() async {
    state = state.copyWith(isLoading: true, error: () => null);
    try {
      final results = <PlatformType, List<Song>>{};
      for (final platform in PlatformRegistry.supportedTypes) {
        try {
          final platformImpl = PlatformRegistry.get(platform);
          final songs = await platformImpl.getRankingList();
          if (songs.isNotEmpty) {
            results[platform] = songs;
          }
        } catch (e) {
          // Skip platforms that fail
        }
      }
      state = state.copyWith(songsByPlatform: results, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: () => '加载排行榜失败');
    }
  }
}

final rankingsProvider =
    StateNotifierProvider<RankingsNotifier, RankingsState>((ref) {
  return RankingsNotifier();
});
