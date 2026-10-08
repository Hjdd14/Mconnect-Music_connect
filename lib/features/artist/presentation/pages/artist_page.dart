import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/platform_http.dart';
import '../../../../core/share/song_actions.dart';
import '../../../../core/theme/platform_accent.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../models/album.dart';
import '../../../../models/artist.dart';
import '../../../../models/platform_type.dart';
import '../../../download/presentation/widgets/download_button.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/artist_provider.dart';

/// Artist page: avatar, bio, counts, 热门歌曲 和 专辑列表.
class ArtistPage extends ConsumerStatefulWidget {
  const ArtistPage({
    super.key,
    required this.platform,
    required this.artistId,
    this.artistName,
  });

  final PlatformType platform;
  final String artistId;
  final String? artistName;

  @override
  ConsumerState<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends ConsumerState<ArtistPage> {
  ArtistKey get _key => (platform: widget.platform, artistId: widget.artistId);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(artistPageProvider(_key));
    final accent = PlatformAccent.colorOf(context, widget.platform);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.artistName ?? '歌手'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(artistPageProvider(_key)),
          ),
        ],
      ),
      body: async.when(
        loading: () => const AsyncStateView.loading(),
        error: (error, _) {
          final typed = apiExceptionOf(error);
          return AsyncStateView.error(
            title: typed.message,
            message: typed.details,
            onRetry: () => ref.invalidate(artistPageProvider(_key)),
          );
        },
        data: (data) {
          if (data.isEmpty) {
            // Nothing to show is not a failure. The `artistError` reason (e.g.
            // the platform answered but every section came back empty) is still
            // surfaced, but no retry is offered because there is nothing to
            // retry — the shared contract draws that line.
            return AsyncStateView.empty(
              title: '暂无艺人信息',
              message: data.artistError,
              icon: Icons.person_off_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(artistPageProvider(_key)),
            child: AppScrollbar(
              builder: (controller) => ListView(
                controller: controller,
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _ArtistHeader(
                    artist: data.artist,
                    fallbackName: widget.artistName ?? '歌手',
                    platform: widget.platform,
                    accent: accent,
                    error: data.artistError,
                    onPlayAll: data.topSongs.isEmpty
                        ? null
                        : () => ref
                              .read(playerProvider.notifier)
                              .playPlaylist(data.topSongs),
                  ),
                  const _SectionTitle(title: '专辑'),
                  if (data.albums.isNotEmpty)
                    SizedBox(
                      height: 172,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: data.albums.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) => _AlbumCard(
                          album: data.albums[index],
                          platform: widget.platform,
                          accent: accent,
                        ),
                      ),
                    )
                  else if (data.albumsError != null)
                    _InlineError(message: data.albumsError!)
                  else
                    const _InlineHint(text: '暂无专辑信息'),
                  const _SectionTitle(title: '热门歌曲'),
                  if (data.topSongsError != null)
                    _InlineError(message: data.topSongsError!)
                  else if (data.topSongs.isEmpty)
                    const _InlineHint(text: '暂无热门歌曲')
                  else
                    for (var i = 0; i < data.topSongs.length; i++)
                      ListTile(
                        onTap: () => ref
                            .read(playerProvider.notifier)
                            .playPlaylist(data.topSongs, startIndex: i),
                        onLongPress: () => showSongActionsMenu(
                          context,
                          ref,
                          song: data.topSongs[i],
                        ),
                        leading: SizedBox(
                          width: 28,
                          child: Text(
                            '${i + 1}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ),
                        title: Text(
                          data.topSongs[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          data.topSongs[i].album?.name ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        trailing: DownloadButton(
                          song: data.topSongs[i],
                          size: 22,
                        ),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({
    required this.artist,
    required this.fallbackName,
    required this.platform,
    required this.accent,
    required this.error,
    required this.onPlayAll,
  });

  final Artist? artist;
  final String fallbackName;
  final PlatformType platform;
  final Color accent;
  final String? error;
  final VoidCallback? onPlayAll;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final counts = <String>[
      if (artist?.songCount != null) '${artist!.songCount} 首歌曲',
      if (artist?.albumCount != null) '${artist!.albumCount} 张专辑',
      if (artist?.fansCount != null) '${artist!.fansCount} 粉丝',
    ];
    final brief = artist?.briefDesc?.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(url: artist?.avatarUrl, accent: accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artist?.name ?? fallbackName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      platform.displayName,
                      style: TextStyle(fontSize: 12, color: cs.outline),
                    ),
                    if (counts.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        counts.join(' · '),
                        style: TextStyle(fontSize: 12, color: cs.outline),
                      ),
                    ],
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: onPlayAll,
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('播放全部'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            _InlineError(message: error!),
          ],
          if (brief != null && brief.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              brief,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: cs.outline, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.accent});

  final String? url;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 96,
      height: 96,
      color: accent.withValues(alpha: 0.12),
      child: Icon(Icons.person, color: accent, size: 40),
    );
    return ClipOval(
      child: url == null || url!.isEmpty
          ? placeholder
          : CachedNetworkImage(
              imageUrl: url!,
              width: 96,
              height: 96,
              memCacheWidth: 192,
              fit: BoxFit.cover,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.album,
    required this.platform,
    required this.accent,
  });

  final Album album;
  final PlatformType platform;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = Container(
      height: 110,
      width: 110,
      color: accent.withValues(alpha: 0.12),
      child: Icon(Icons.album, color: accent),
    );
    return SizedBox(
      width: 110,
      child: InkWell(
        onTap: () => context.push(
          '/album/${platform.name}/${Uri.encodeComponent(album.id)}'
          '?name=${Uri.encodeComponent(album.name)}',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: album.coverUrl == null || album.coverUrl!.isEmpty
                  ? placeholder
                  : CachedNetworkImage(
                      imageUrl: album.coverUrl!,
                      height: 110,
                      width: 110,
                      memCacheWidth: 220,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => placeholder,
                      errorWidget: (_, _, _) => placeholder,
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              album.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              album.releaseDate == null ? '' : '${album.releaseDate!.year}',
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _InlineHint extends StatelessWidget {
  const _InlineHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        text,
        // Contract rule 2: body copy uses the theme's secondary-text role.
        // `outline` is a *border* colour and fails contrast as copy.
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              // Rule 2, as above: this is an error *message*, so it must be
              // readable body copy rather than a border-coloured label.
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
