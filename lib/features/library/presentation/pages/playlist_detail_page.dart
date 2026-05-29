import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';
import '../../../../platform/base/platform_registry.dart';
import '../../../download/presentation/widgets/download_button.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/my_playlists_provider.dart';

class PlaylistDetailPage extends ConsumerStatefulWidget {
  final PlatformType platform;
  final String playlistId;
  final String playlistName;
  final String? coverUrl;

  const PlaylistDetailPage({
    super.key,
    required this.platform,
    required this.playlistId,
    required this.playlistName,
    this.coverUrl,
  });

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  late Future<List<Song>> _songsFuture;

  @override
  void initState() {
    super.initState();
    _songsFuture = _loadSongs();
  }

  Future<List<Song>> _loadSongs() {
    if (widget.platform == PlatformType.local) {
      return ref
          .read(myPlaylistsProvider.notifier)
          .getSongs(widget.playlistId)
          .timeout(const Duration(seconds: 8));
    }
    final platform = PlatformRegistry.get(widget.platform);
    return platform
        .getPlaylistDetail(widget.playlistId)
        .timeout(const Duration(seconds: 15));
  }

  void _retry() {
    setState(() {
      _songsFuture = _loadSongs();
    });
  }

  void _playSongs(List<Song> songs, int index) {
    if (songs.isEmpty) return;
    unawaited(
      ref.read(playerProvider.notifier).playPlaylist(songs, startIndex: index),
    );
  }

  Future<void> _removeLocalSong(Song song) async {
    final ok = await ref
        .read(myPlaylistsProvider.notifier)
        .removeSong(widget.playlistId, song);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(ok ? '已从歌单删除' : '删除失败')));
    if (ok) _retry();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('歌单详情')),
      body: FutureBuilder<List<Song>>(
        future: _songsFuture,
        builder: (context, snapshot) {
          final songs = snapshot.data ?? const <Song>[];
          return AppScrollbar(
            builder: (controller) => CustomScrollView(
              controller: controller,
              slivers: [
                SliverToBoxAdapter(
                  child: _PlaylistHeader(
                    platform: widget.platform,
                    name: widget.playlistName,
                    coverUrl:
                        widget.coverUrl ??
                        (songs.isNotEmpty ? songs.first.coverUrl : null),
                    songCount: songs.length,
                    isLoading:
                        snapshot.connectionState == ConnectionState.waiting,
                    onPlayAll: songs.isEmpty
                        ? null
                        : () => _playSongs(songs, 0),
                  ),
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '加载歌单失败',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _retry,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (songs.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        '歌单暂无歌曲',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount: songs.length,
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      return ListTile(
                        leading: SizedBox(
                          width: 40,
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.outline,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          song.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          song.artistNames,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                            fontSize: 13,
                          ),
                        ),
                        trailing: widget.platform == PlatformType.local
                            ? PopupMenuButton<String>(
                                tooltip: '歌曲操作',
                                onSelected: (value) {
                                  if (value == 'remove') {
                                    unawaited(_removeLocalSong(song));
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'remove',
                                    child: ListTile(
                                      leading: Icon(Icons.delete_outline),
                                      title: Text('从歌单删除'),
                                    ),
                                  ),
                                ],
                              )
                            : DownloadButton(song: song, size: 22),
                        onTap: () => _playSongs(songs, index),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PlaylistHeader extends StatelessWidget {
  final PlatformType platform;
  final String name;
  final String? coverUrl;
  final int songCount;
  final bool isLoading;
  final VoidCallback? onPlayAll;

  const _PlaylistHeader({
    required this.platform,
    required this.name,
    required this.coverUrl,
    required this.songCount,
    required this.isLoading,
    required this.onPlayAll,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: coverUrl != null && coverUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: coverUrl!,
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                    memCacheWidth: 192,
                    placeholder: (_, __) =>
                        _CoverPlaceholder(color: cs.primaryContainer),
                    errorWidget: (_, __, ___) =>
                        _CoverPlaceholder(color: cs.primaryContainer),
                  )
                : _CoverPlaceholder(color: cs.primaryContainer),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? '未命名歌单' : name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${platform.displayName} · ${isLoading ? '加载中' : '$songCount 首'}',
                  style: TextStyle(color: cs.outline),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onPlayAll,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('播放全部'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  final Color color;

  const _CoverPlaceholder({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      color: color,
      child: const Icon(Icons.queue_music),
    );
  }
}
