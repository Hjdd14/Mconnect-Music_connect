import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/playlist.dart';
import '../../../../models/song.dart';
import '../../../../models/platform_type.dart';
import '../../../../platform/base/platform_registry.dart';
import '../../../download/presentation/widgets/download_button.dart';
import '../../../player/presentation/providers/player_provider.dart';

final selectedPlatformProvider = StateProvider<PlatformType>(
  (ref) => PlatformType.netease,
);

final searchQueryProvider = StateProvider<String>((ref) => '');

enum SearchMode { songs, playlists }

final searchModeProvider = StateProvider<SearchMode>((ref) => SearchMode.songs);

final searchResultsProvider = FutureProvider.autoDispose<List<Song>>((
  ref,
) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];
  if (ref.watch(searchModeProvider) != SearchMode.songs) return [];
  final platformType = ref.watch(selectedPlatformProvider);
  final platform = PlatformRegistry.get(platformType);
  return platform.search(query);
});

final playlistSearchResultsProvider =
    FutureProvider.autoDispose<List<Playlist>>((ref) async {
      final query = ref.watch(searchQueryProvider);
      if (query.isEmpty) return [];
      if (ref.watch(searchModeProvider) != SearchMode.playlists) return [];
      final platformType = ref.watch(selectedPlatformProvider);
      final platform = PlatformRegistry.get(platformType);
      return platform.searchPlaylists(query);
    });

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _hasText = ValueNotifier<bool>(false);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _hasText.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).state = _controller.text.trim();
    });
  }

  void _submitSearch() {
    _debounce?.cancel();
    ref.read(searchQueryProvider.notifier).state = _controller.text.trim();
    _focusNode.unfocus();
  }

  void _clearSearch() {
    _debounce?.cancel();
    _controller.clear();
    _hasText.value = false;
    ref.read(searchQueryProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlatform = ref.watch(selectedPlatformProvider);
    final mode = ref.watch(searchModeProvider);
    final query = ref.watch(searchQueryProvider);
    final results = ref.watch(searchResultsProvider);
    final playlistResults = ref.watch(playlistSearchResultsProvider);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: PlatformType.musicServices.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final type = PlatformType.musicServices[index];
                      final isSelected = type == selectedPlatform;
                      return ChoiceChip(
                        label: Text(type.displayName),
                        selected: isSelected,
                        onSelected: (_) {
                          ref.read(selectedPlatformProvider.notifier).state =
                              type;
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<SearchMode>(
                    segments: const [
                      ButtonSegment(
                        value: SearchMode.songs,
                        icon: Icon(Icons.music_note),
                        label: Text('歌曲'),
                      ),
                      ButtonSegment(
                        value: SearchMode.playlists,
                        icon: Icon(Icons.queue_music),
                        label: Text('歌单'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (values) {
                      ref.read(searchModeProvider.notifier).state =
                          values.first;
                    },
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: mode == SearchMode.songs ? '搜索歌曲、歌手、专辑' : '搜索歌单',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: ValueListenableBuilder<bool>(
                      valueListenable: _hasText,
                      builder: (_, hasText, __) => hasText
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: _clearSearch,
                            )
                          : const SizedBox.shrink(),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submitSearch(),
                  onChanged: (v) {
                    _hasText.value = v.isNotEmpty;
                    _scheduleSearch();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: mode == SearchMode.songs
                ? results.when(
                    data: (songs) {
                      if (songs.isEmpty) {
                        return _SearchEmptyState(
                          hasQuery: query.trim().isNotEmpty,
                        );
                      }
                      return AppScrollbar(
                        builder: (controller) => ListView.builder(
                          controller: controller,
                          itemCount: songs.length,
                          itemBuilder: (context, index) =>
                              _SongTile(songs: songs, index: index),
                        ),
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => _ErrorState(error: e),
                  )
                : playlistResults.when(
                    data: (playlists) {
                      if (playlists.isEmpty) {
                        return _SearchEmptyState(
                          hasQuery: query.trim().isNotEmpty,
                        );
                      }
                      return AppScrollbar(
                        builder: (controller) => ListView.builder(
                          controller: controller,
                          itemCount: playlists.length,
                          itemBuilder: (context, index) =>
                              _PlaylistTile(playlist: playlists[index]),
                        ),
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => _ErrorState(error: e),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  final bool hasQuery;

  const _SearchEmptyState({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        hasQuery ? '未找到相关内容' : '请输入关键词',
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 8),
          Text(
            '加载失败：$error',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _SongTile extends ConsumerWidget {
  final List<Song> songs;
  final int index;
  final Song song;

  _SongTile({required this.songs, required this.index}) : song = songs[index];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: song.coverUrl != null
            ? CachedNetworkImage(
                imageUrl: song.coverUrl!,
                width: 48,
                height: 48,
                memCacheWidth: 96,
                fit: BoxFit.cover,
                placeholder: (_, __) => _ArtPlaceholder(icon: Icons.music_note),
                errorWidget: (_, __, ___) =>
                    _ArtPlaceholder(icon: Icons.music_note),
              )
            : _ArtPlaceholder(icon: Icons.music_note),
      ),
      title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        song.album?.name != null
            ? '${song.artistNames} - ${song.album!.name}'
            : song.artistNames,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Theme.of(context).colorScheme.outline,
          fontSize: 13,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              song.platform.displayName.substring(0, 2),
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          DownloadButton(song: song, size: 22),
          const SizedBox(width: 2),
          IconButton(
            icon: const Icon(Icons.play_circle_outline),
            onPressed: () {
              ref
                  .read(playerProvider.notifier)
                  .playPlaylist(songs, startIndex: index);
            },
          ),
        ],
      ),
      onTap: () {
        ref
            .read(playerProvider.notifier)
            .playPlaylist(songs, startIndex: index);
      },
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final Playlist playlist;
  const _PlaylistTile({required this.playlist});

  String _route() {
    final query = Uri(
      queryParameters: {
        'name': playlist.name,
        if (playlist.coverUrl != null && playlist.coverUrl!.isNotEmpty)
          'cover': playlist.coverUrl!,
      },
    ).query;
    return '/playlist/${playlist.platform.name}/${Uri.encodeComponent(playlist.id)}'
        '${query.isEmpty ? '' : '?$query'}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: playlist.coverUrl != null
            ? CachedNetworkImage(
                imageUrl: playlist.coverUrl!,
                width: 48,
                height: 48,
                memCacheWidth: 96,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    _ArtPlaceholder(icon: Icons.queue_music),
                errorWidget: (_, __, ___) =>
                    _ArtPlaceholder(icon: Icons.queue_music),
              )
            : _ArtPlaceholder(icon: Icons.queue_music),
      ),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${playlist.songCount} 首${playlist.creatorName == null ? '' : ' - ${playlist.creatorName}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: cs.outline, fontSize: 13),
      ),
      trailing: IconButton(
        icon: Icon(playlist.collected ? Icons.bookmark : Icons.bookmark_border),
        onPressed: () async {
          final ok = await PlatformRegistry.get(playlist.platform)
              .collectPlaylist(playlist.id)
              .timeout(const Duration(seconds: 12), onTimeout: () => false);
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(ok ? '已收藏歌单' : '收藏失败')));
        },
      ),
      onTap: () => context.push(_route()),
    );
  }
}

class _ArtPlaceholder extends StatelessWidget {
  final IconData icon;
  const _ArtPlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(icon, size: 20),
    );
  }
}
