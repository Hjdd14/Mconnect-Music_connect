import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/share/song_actions.dart';
import '../../../../core/theme/platform_accent.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';
import '../../../../platform/base/music_platform.dart';
import '../../../download/presentation/widgets/download_button.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/new_songs_provider.dart';

/// 新歌速递 — new releases per platform and region.
///
/// A platform that cannot serve the selected region says so in place of the
/// list (`该地区暂不支持` / `暂不支持新歌速递`), because an empty list is
/// indistinguishable from "no new songs today".
class NewSongsPage extends ConsumerStatefulWidget {
  const NewSongsPage({super.key});

  @override
  ConsumerState<NewSongsPage> createState() => _NewSongsPageState();
}

class _NewSongsPageState extends ConsumerState<NewSongsPage> {
  @override
  void initState() {
    super.initState();
    final state = ref.read(newSongsProvider);
    if (!state.hasAnyData && !state.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(newSongsProvider.notifier).load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newSongsProvider);
    final platforms = PlatformType.musicServices.where((platform) {
      return state.songsForPlatform(platform).isNotEmpty ||
          state.noticeForPlatform(platform) != null ||
          state.errorForPlatform(platform) != null;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('新歌速递'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(newSongsProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: NewSongRegionLabels.ordered.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final region = NewSongRegionLabels.ordered[index];
                return ChoiceChip(
                  label: Text(newSongRegionLabels[region]!),
                  selected: state.region == region,
                  onSelected: (_) =>
                      ref.read(newSongsProvider.notifier).load(region: region),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(newSongsProvider.notifier).refresh(),
              child: AppScrollbar(
                builder: (controller) => ListView(
                  controller: controller,
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (state.isLoading && !state.hasAnyData)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    for (final platform in platforms)
                      _PlatformNewSongsSection(
                        platform: platform,
                        songs: state.songsForPlatform(platform),
                        notice: state.noticeForPlatform(platform),
                        error: state.errorForPlatform(platform),
                        onRetry: () =>
                            ref.read(newSongsProvider.notifier).refresh(),
                        onPlay: (index, songs) => ref
                            .read(playerProvider.notifier)
                            .playPlaylist(songs, startIndex: index),
                      ),
                    if (!state.isLoading && platforms.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: Text('暂无新歌数据，下拉刷新重试')),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Region order for the chips (the enum's declaration order is the display
/// order; kept here so the page does not depend on that by accident).
class NewSongRegionLabels {
  NewSongRegionLabels._();

  static const List<NewSongRegion> ordered = [
    NewSongRegion.all,
    NewSongRegion.chinese,
    NewSongRegion.western,
    NewSongRegion.japanese,
    NewSongRegion.korean,
    NewSongRegion.hongKongTaiwan,
  ];
}

class _PlatformNewSongsSection extends StatelessWidget {
  const _PlatformNewSongsSection({
    required this.platform,
    required this.songs,
    required this.notice,
    required this.error,
    required this.onRetry,
    required this.onPlay,
  });

  final PlatformType platform;
  final List<Song> songs;
  final String? notice;
  final String? error;
  final VoidCallback onRetry;
  final void Function(int index, List<Song> songs) onPlay;

  @override
  Widget build(BuildContext context) {
    final accent = PlatformAccent.colorOf(context, platform);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                platform.displayName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (songs.isNotEmpty)
                Text(
                  '${songs.length} 首',
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: cs.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error!,
                    style: TextStyle(fontSize: 12, color: cs.error),
                  ),
                ),
                TextButton(onPressed: onRetry, child: const Text('重试')),
              ],
            ),
          ),
        if (notice != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: cs.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    notice!,
                    key: ValueKey('new-songs-notice-${platform.name}'),
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                ),
              ],
            ),
          ),
        for (var i = 0; i < songs.length; i++)
          _NewSongTile(
            song: songs[i],
            accent: accent,
            onTap: () => onPlay(i, songs),
          ),
      ],
    );
  }
}

class _NewSongTile extends ConsumerWidget {
  const _NewSongTile({
    required this.song,
    required this.accent,
    required this.onTap,
  });

  final Song song;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: 48,
      height: 48,
      color: accent.withValues(alpha: 0.12),
      child: Icon(Icons.fiber_new, color: accent),
    );
    return ListTile(
      onTap: onTap,
      onLongPress: () => showSongActionsMenu(context, ref, song: song),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: song.coverUrl == null || song.coverUrl!.isEmpty
            ? placeholder
            : CachedNetworkImage(
                imageUrl: song.coverUrl!,
                width: 48,
                height: 48,
                memCacheWidth: 96,
                fit: BoxFit.cover,
                placeholder: (_, _) => placeholder,
                errorWidget: (_, _, _) => placeholder,
              ),
      ),
      title: Text(
        song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15),
      ),
      subtitle: Text(
        song.album?.name != null && song.album!.name.isNotEmpty
            ? '${song.artistNames} · ${song.album!.name}'
            : song.artistNames,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: cs.outline),
      ),
      trailing: DownloadButton(song: song, size: 22),
    );
  }
}
