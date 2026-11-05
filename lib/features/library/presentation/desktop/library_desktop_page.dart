import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/desktop/desktop_empty_state.dart';
import '../../../../core/desktop/desktop_media_card.dart';
import '../../../../core/desktop/desktop_page_scaffold.dart';
import '../../../../core/desktop/desktop_song_table.dart';
import '../../../../core/desktop/desktop_tokens.dart';
import '../../../../core/theme/platform_accent.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/playlist.dart';
import '../../../../models/song.dart';
import '../../../download/presentation/widgets/download_button.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/likes_provider.dart';
import '../providers/my_playlists_provider.dart';

enum _LibraryTab { songs, albums, artists, playlists }

/// Desktop library.
///
/// The phone library is a navigation list; a desktop library should be the
/// content itself. Everything here is derived from the two local stores that
/// already exist — likes (drift) and "我的歌单" (local JSON) — so there is no new
/// network surface and nothing to log in for.
class LibraryDesktopPage extends ConsumerStatefulWidget {
  const LibraryDesktopPage({super.key});

  @override
  ConsumerState<LibraryDesktopPage> createState() => _LibraryDesktopPageState();
}

class _LibraryDesktopPageState extends ConsumerState<LibraryDesktopPage> {
  _LibraryTab _tab = _LibraryTab.songs;
  String _sortKey = DesktopSongColumn.title;
  bool _sortAscending = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final likes = ref.watch(likesProvider);
    final myPlaylists = ref.watch(myPlaylistsProvider);
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));

    final songs = likes.songs;
    final albums = _groupByAlbum(songs);
    final artists = _groupByArtist(songs);

    return DesktopPageScaffold(
      title: '音乐库',
      subtitle:
          '${songs.length} 首喜欢 · ${albums.length} 张专辑 · '
          '${artists.length} 位艺人 · ${myPlaylists.playlists.length} 个歌单',
      actions: [
        if (_tab == _LibraryTab.songs && likes.filteredSongs.isNotEmpty)
          FilledButton.icon(
            onPressed: () => unawaited(
              ref
                  .read(playerProvider.notifier)
                  .playPlaylist(
                    sortDesktopSongs(
                      songs,
                      key: _sortKey,
                      ascending: _sortAscending,
                    ),
                    startIndex: 0,
                  ),
            ),
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('播放全部'),
          ),
        IconButton(
          tooltip: '刷新音乐库',
          onPressed: _reload,
          icon: const Icon(Icons.refresh, size: 20),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DesktopTabStrip<_LibraryTab>(
                  tabs: [
                    DesktopTabItem(
                      value: _LibraryTab.songs,
                      label: '歌曲',
                      count: songs.length,
                      icon: Icons.music_note,
                    ),
                    DesktopTabItem(
                      value: _LibraryTab.albums,
                      label: '专辑',
                      count: albums.length,
                      icon: Icons.album_outlined,
                    ),
                    DesktopTabItem(
                      value: _LibraryTab.artists,
                      label: '艺人',
                      count: artists.length,
                      icon: Icons.person_outline,
                    ),
                    DesktopTabItem(
                      value: _LibraryTab.playlists,
                      label: '歌单',
                      count: myPlaylists.playlists.length,
                      icon: Icons.queue_music,
                    ),
                  ],
                  selected: _tab,
                  onSelected: (value) => setState(() => _tab = value),
                ),
              ),
              const SizedBox(width: DesktopSpacing.sm),
              TextButton.icon(
                onPressed: () => context.push('/history'),
                icon: const Icon(Icons.history, size: 16),
                label: const Text('最近播放'),
              ),
              TextButton.icon(
                onPressed: () => context.push('/platform-playlists'),
                icon: const Icon(Icons.cloud_outlined, size: 16),
                label: const Text('平台歌单'),
              ),
            ],
          ),
          const SizedBox(height: DesktopSpacing.md),
          if (likes.error != null &&
              songs.isEmpty &&
              _tab != _LibraryTab.playlists)
            Expanded(
              child: DesktopEmptyState(
                // Likes are a local drift table (no login involved), so a
                // failure here is a local read error — not a missing account.
                icon: Icons.error_outline,
                title: '读取喜欢的歌曲失败',
                message: likes.error ?? '本地音乐库读取失败，可以稍后重试。',
                action: FilledButton.tonal(
                  onPressed: () =>
                      unawaited(ref.read(likesProvider.notifier).loadLikes()),
                  child: const Text('重试'),
                ),
              ),
            )
          else
            Expanded(
              child: switch (_tab) {
                _LibraryTab.songs => _buildSongs(likes, currentSong),
                _LibraryTab.albums => _buildCollections(
                  albums,
                  emptyIcon: Icons.album_outlined,
                  emptyTitle: '还没有专辑',
                  emptyMessage: '喜欢的歌曲会按专辑自动归类到这里',
                ),
                _LibraryTab.artists => _buildCollections(
                  artists,
                  emptyIcon: Icons.person_outline,
                  emptyTitle: '还没有艺人',
                  emptyMessage: '喜欢的歌曲会按艺人自动归类到这里',
                ),
                _LibraryTab.playlists => _buildPlaylists(myPlaylists, scheme),
              },
            ),
        ],
      ),
    );
  }

  void _reload() {
    unawaited(ref.read(likesProvider.notifier).loadLikes());
    unawaited(ref.read(myPlaylistsProvider.notifier).load());
  }

  Widget _buildSongs(LikesState likes, Song? currentSong) {
    final allSongs = likes.songs;
    if (likes.isLoading && allSongs.isEmpty) {
      return const DesktopInlineLoading(label: '正在读取喜欢的歌曲…');
    }
    final visibleSongs = likes.filteredSongs;
    final sorted = sortDesktopSongs(
      visibleSongs,
      key: _sortKey,
      ascending: _sortAscending,
    );
    final filter = likes.filterPlatform;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (allSongs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: DesktopSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: DesktopTabStrip<PlatformType?>(
                    tabs: [
                      const DesktopTabItem<PlatformType?>(
                        value: null,
                        label: '全部',
                      ),
                      for (final platform in PlatformType.musicServices)
                        DesktopTabItem<PlatformType?>(
                          value: platform,
                          label: platform.displayName,
                          icon: PlatformAccent.iconOf(platform),
                        ),
                    ],
                    selected: filter,
                    onSelected: (value) =>
                        ref.read(likesProvider.notifier).setFilter(value),
                  ),
                ),
                const SizedBox(width: DesktopSpacing.sm),
                Text(
                  '显示 ${visibleSongs.length} / ${allSongs.length} 首',
                  style: DesktopText.caption.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: DesktopSongTable(
            songs: sorted,
            currentSong: currentSong,
            sortKey: _sortKey,
            sortAscending: _sortAscending,
            onSort: _toggleSort,
            actionsLabel: '操作',
            onPlay: (index) => unawaited(
              ref
                  .read(playerProvider.notifier)
                  .playPlaylist(sorted, startIndex: index),
            ),
            trailingBuilder: (song, index) => [
              IconButton(
                tooltip: '取消喜欢',
                onPressed: () => unawaited(
                  ref.read(likesProvider.notifier).toggleLike(song),
                ),
                icon: Icon(
                  Icons.favorite,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              DownloadButton(song: song, size: 18),
            ],
            emptyState: DesktopEmptyState(
              icon: Icons.favorite_border,
              title: filter == null ? '还没有喜欢的歌曲' : '这个平台还没有喜欢的歌曲',
              message: filter == null
                  ? '在播放页或歌曲菜单里点「喜欢」，就会出现在这里'
                  : '换一个平台筛选，或者先喜欢几首这个平台的歌',
              action: filter == null
                  ? FilledButton(
                      onPressed: () => context.go('/'),
                      child: const Text('去发现音乐'),
                    )
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCollections(
    List<_CollectionGroup> groups, {
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyMessage,
  }) {
    if (groups.isEmpty) {
      return DesktopEmptyState(
        icon: emptyIcon,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = DesktopSpacing.lg;
        const targetWidth = 180.0;
        final columns = (constraints.maxWidth / (targetWidth + spacing))
            .floor()
            .clamp(2, 8)
            .toInt();
        final itemWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return AppScrollbar(
          builder: (controller) => GridView.builder(
            controller: controller,
            padding: const EdgeInsets.only(
              top: 6,
              bottom: DesktopSpacing.xxxl,
              right: DesktopSpacing.xs,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: spacing,
              mainAxisSpacing: DesktopSpacing.lg,
              // +76 leaves room for the card's own hover lift (3) and the two
              // text rows below the cover, so a hover never overflow-clips.
              mainAxisExtent: itemWidth + 76,
            ),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return DesktopMediaCard(
                title: group.title,
                subtitle: '${group.subtitle} · ${group.songs.length} 首',
                imageUrl: group.coverUrl,
                width: itemWidth,
                onTap: () => _playGroup(group),
                onPlay: () => _playGroup(group),
              );
            },
          ),
        );
      },
    );
  }

  void _playGroup(_CollectionGroup group) {
    unawaited(
      ref
          .read(playerProvider.notifier)
          .playPlaylist(group.songs, startIndex: 0),
    );
  }

  Widget _buildPlaylists(MyPlaylistsState state, ColorScheme scheme) {
    final playlists = state.playlists;
    if (playlists.isEmpty && !state.isLoading) {
      return DesktopEmptyState(
        icon: Icons.playlist_add,
        title: '还没有自建歌单',
        message: '把喜欢的歌曲整理成自己的歌单，全部保存在本地',
        action: FilledButton.icon(
          onPressed: () => unawaited(_createPlaylist()),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('新建歌单'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: DesktopSpacing.sm),
          child: Row(
            children: [
              Text(
                '我的歌单',
                style: DesktopText.title.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(width: DesktopSpacing.sm),
              Text(
                '共 ${playlists.length} 个 · 保存在本地',
                style: DesktopText.caption.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: state.isSaving
                    ? null
                    : () => unawaited(_createPlaylist()),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建歌单'),
              ),
            ],
          ),
        ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: DesktopSpacing.sm),
            child: Text(
              state.error!,
              style: DesktopText.caption.copyWith(color: scheme.error),
            ),
          ),
        Expanded(
          child: state.isLoading && playlists.isEmpty
              ? const DesktopInlineLoading(label: '正在读取我的歌单…')
              : ListView.separated(
                  itemCount: playlists.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 2),
                  itemBuilder: (context, index) => _PlaylistRow(
                    playlist: playlists[index],
                    onOpen: () => _openPlaylist(playlists[index]),
                    onDelete: () =>
                        unawaited(_deletePlaylist(playlists[index])),
                  ),
                ),
        ),
      ],
    );
  }

  void _openPlaylist(Playlist playlist) {
    final query = Uri(
      queryParameters: {
        'name': playlist.name,
        if (playlist.coverUrl != null && playlist.coverUrl!.isNotEmpty)
          'cover': playlist.coverUrl!,
      },
    ).query;
    final id = Uri.encodeComponent(playlist.id);
    context.push(
      '/playlist/${playlist.platform.name}/$id${query.isEmpty ? '' : '?$query'}',
    );
  }

  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建歌单'),
        content: SizedBox(
          width: 320,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '歌单名称'),
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    // No snack bar here: the desktop shell has no Scaffold of its own, and the
    // list itself is the confirmation (the new row appears; the notifier's
    // error is rendered inline above the rows).
    await ref.read(myPlaylistsProvider.notifier).create(name);
  }

  Future<void> _deletePlaylist(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定要删除「${playlist.name}」吗？只会删除歌单，不会删除本地音乐文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // The list row disappearing is the feedback; a failure is surfaced by
    // `MyPlaylistsState.error` which is rendered above the rows.
    await ref.read(myPlaylistsProvider.notifier).deletePlaylist(playlist.id);
  }

  void _toggleSort(String key) {
    setState(() {
      if (_sortKey == key) {
        _sortAscending = !_sortAscending;
      } else {
        _sortKey = key;
        _sortAscending = true;
      }
    });
  }

  /// Groups liked songs by album name.
  ///
  /// Album ids are empty on rows rebuilt from the database, so the grouping key
  /// is the display name plus the album's artist — not `Album.id`, which would
  /// merge every album of the same name into one.
  List<_CollectionGroup> _groupByAlbum(List<Song> songs) {
    final byKey = <String, _CollectionGroup>{};
    for (final song in songs) {
      final albumName = song.album?.name.trim();
      final title = (albumName == null || albumName.isEmpty)
          ? '未知专辑'
          : albumName;
      final artist = song.album?.artistName?.trim();
      final subtitle = (artist == null || artist.isEmpty)
          ? song.artistNames
          : artist;
      final key = '$title|$subtitle';
      final group = byKey.putIfAbsent(
        key,
        () => _CollectionGroup(title: title, subtitle: subtitle),
      );
      group.songs.add(song);
      group.coverUrl ??= song.coverUrl ?? song.album?.coverUrl;
    }
    return _sortedGroups(byKey.values);
  }

  List<_CollectionGroup> _groupByArtist(List<Song> songs) {
    final byKey = <String, _CollectionGroup>{};
    for (final song in songs) {
      final name = song.artists.isEmpty ? '' : song.artists.first.name.trim();
      final title = name.isEmpty ? '未知艺人' : name;
      final group = byKey.putIfAbsent(
        title,
        () => _CollectionGroup(title: title, subtitle: '艺人'),
      );
      group.songs.add(song);
      group.coverUrl ??= song.coverUrl ?? song.album?.coverUrl;
    }
    return _sortedGroups(byKey.values);
  }

  List<_CollectionGroup> _sortedGroups(Iterable<_CollectionGroup> groups) {
    final sorted = groups.toList()
      ..sort((a, b) {
        final byCount = b.songs.length.compareTo(a.songs.length);
        if (byCount != 0) return byCount;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    return sorted;
  }
}

class _CollectionGroup {
  final String title;
  final String subtitle;
  final List<Song> songs = <Song>[];
  String? coverUrl;

  _CollectionGroup({required this.title, required this.subtitle});
}

class _PlaylistRow extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _PlaylistRow({
    required this.playlist,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: DesktopRadii.smAll,
      child: InkWell(
        borderRadius: DesktopRadii.smAll,
        hoverColor: scheme.onSurface.withValues(alpha: 0.05),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesktopSpacing.sm,
            vertical: 6,
          ),
          child: Row(
            children: [
              DesktopCoverArt(
                url: playlist.coverUrl,
                size: 44,
                icon: Icons.queue_music,
              ),
              const SizedBox(width: DesktopSpacing.md),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopText.bodyStrong.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${playlist.songCount} 首 · 本地歌单',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DesktopText.caption.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: onOpen, child: const Text('打开')),
              IconButton(
                tooltip: '删除歌单',
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline, size: 16, color: scheme.error),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
