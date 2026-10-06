import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/platform_http.dart';
import '../../../../core/share/song_actions.dart';
import '../../../../core/theme/platform_accent.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/album.dart';
import '../../../../models/audio_quality.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';
import '../../../download/presentation/providers/download_provider.dart';
import '../../../download/presentation/widgets/download_button.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/album_provider.dart';

/// Album detail: cover, release metadata and the track list.
///
/// Replaces the Wave 0 placeholder. Failure paths stay honest: a platform that
/// does not implement album pages reports `暂不支持`, and an empty track list
/// says so instead of rendering a blank page.
class AlbumPage extends ConsumerStatefulWidget {
  const AlbumPage({
    super.key,
    required this.platform,
    required this.albumId,
    this.albumName,
  });

  final PlatformType platform;
  final String albumId;
  final String? albumName;

  @override
  ConsumerState<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends ConsumerState<AlbumPage> {
  AlbumKey get _key => (platform: widget.platform, albumId: widget.albumId);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(albumDetailProvider(_key));
    final accent = PlatformAccent.colorOf(context, widget.platform);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.albumName ?? '专辑'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(albumDetailProvider(_key)),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _AlbumMessage(
          icon: Icons.error_outline,
          message: apiExceptionOf(error).message,
          details: apiExceptionOf(error).details,
          onRetry: () => ref.invalidate(albumDetailProvider(_key)),
        ),
        data: (data) {
          if (data.isEmpty) {
            return _AlbumMessage(
              icon: Icons.album_outlined,
              message: '暂无专辑信息',
              onRetry: () => ref.invalidate(albumDetailProvider(_key)),
            );
          }
          final songs = data.songs;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(albumDetailProvider(_key)),
            child: AppScrollbar(
              builder: (controller) => ListView.builder(
                controller: controller,
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: songs.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _AlbumHeader(
                      platform: widget.platform,
                      fallbackName: widget.albumName,
                      album: data.album,
                      songCount: songs.length,
                      accent: accent,
                      onPlayAll: songs.isEmpty
                          ? null
                          : () => ref
                                .read(playerProvider.notifier)
                                .playPlaylist(songs),
                      onCacheAll: songs.isEmpty
                          ? null
                          : () => _cacheAll(songs),
                      onOpenArtist: data.album?.artistId == null
                          ? null
                          : () => context.push(
                              '/artist/${widget.platform.name}/'
                              '${Uri.encodeComponent(data.album!.artistId!)}'
                              '?name=${Uri.encodeComponent(data.album!.artistName ?? '')}',
                            ),
                    );
                  }
                  final i = index - 1;
                  return _AlbumTrackTile(
                    song: songs[i],
                    index: i,
                    accent: accent,
                    onTap: () => ref
                        .read(playerProvider.notifier)
                        .playPlaylist(songs, startIndex: i),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _cacheAll(List<Song> songs) async {
    final report = await ref
        .read(downloadProvider.notifier)
        .cacheSongs(songs, quality: AudioLevel.low);
    if (!mounted) return;
    final started = report.started + report.queued;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已加入离线缓存 $started 首'
          '${report.skipped > 0 ? '，跳过 ${report.skipped} 首' : ''}',
        ),
      ),
    );
  }
}

class _AlbumHeader extends StatelessWidget {
  const _AlbumHeader({
    required this.platform,
    required this.fallbackName,
    required this.album,
    required this.songCount,
    required this.accent,
    required this.onPlayAll,
    required this.onCacheAll,
    required this.onOpenArtist,
  });

  final PlatformType platform;
  final String? fallbackName;
  final Album? album;
  final int songCount;
  final Color accent;
  final VoidCallback? onPlayAll;
  final VoidCallback? onCacheAll;
  final VoidCallback? onOpenArtist;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chips = <String>[
      '$songCount 首',
      if (album?.releaseDate != null) _formatDate(album!.releaseDate!),
      if (album?.company != null && album!.company!.isNotEmpty) album!.company!,
      if (album?.genre != null && album!.genre!.isNotEmpty) album!.genre!,
      if (album?.language != null && album!.language!.isNotEmpty)
        album!.language!,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AlbumCover(
                coverUrl: album?.coverUrl,
                accent: accent,
                size: 120,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album?.name ?? fallbackName ?? '专辑',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (album?.artistName != null &&
                        album!.artistName!.isNotEmpty)
                      InkWell(
                        onTap: onOpenArtist,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_outline, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                album!.artistName!,
                                style: TextStyle(fontSize: 13, color: accent),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      platform.displayName,
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final chip in chips)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              chip,
                              style: TextStyle(fontSize: 11, color: accent),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (album?.description != null &&
              album!.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              album!.description!.trim(),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: cs.outline, height: 1.5),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: onPlayAll,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('播放全部'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onCacheAll,
                icon: const Icon(Icons.download_for_offline_outlined, size: 18),
                label: const Text('整张缓存'),
              ),
            ],
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class _AlbumTrackTile extends ConsumerWidget {
  const _AlbumTrackTile({
    required this.song,
    required this.index,
    required this.accent,
    required this.onTap,
  });

  final Song song;
  final int index;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final trackNumber = song.trackNumber;
    return ListTile(
      onTap: onTap,
      onLongPress: () => showSongActionsMenu(context, ref, song: song),
      leading: SizedBox(
        width: 32,
        child: Text(
          '${trackNumber ?? index + 1}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: cs.outline),
        ),
      ),
      title: Text(
        song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15),
      ),
      subtitle: Text(
        song.artistNames,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: cs.outline),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (song.duration > Duration.zero)
            Text(
              _formatDuration(song.duration),
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
          const SizedBox(width: 4),
          DownloadButton(song: song, size: 22),
        ],
      ),
    );
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _AlbumCover extends StatelessWidget {
  const _AlbumCover({
    required this.coverUrl,
    required this.accent,
    required this.size,
  });

  final String? coverUrl;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: accent.withValues(alpha: 0.12),
      child: Icon(Icons.album, color: accent, size: size * 0.4),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: coverUrl == null || coverUrl!.isEmpty
          ? placeholder
          : CachedNetworkImage(
              imageUrl: coverUrl!,
              width: size,
              height: size,
              memCacheWidth: (size * 2).round(),
              fit: BoxFit.cover,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),
    );
  }
}

class _AlbumMessage extends StatelessWidget {
  const _AlbumMessage({
    required this.icon,
    required this.message,
    required this.onRetry,
    this.details,
  });

  final IconData icon;
  final String message;
  final String? details;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (details != null) ...[
              const SizedBox(height: 6),
              Text(
                details!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
