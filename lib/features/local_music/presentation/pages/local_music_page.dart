import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/song.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../data/local_track_store.dart';
import '../../domain/local_library_grouping.dart';
import '../providers/local_music_provider.dart';

class LocalMusicPage extends ConsumerWidget {
  const LocalMusicPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(localMusicProvider);
    final notifier = ref.read(localMusicProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('本地音乐'),
        actions: [
          IconButton(
            tooltip: '重新扫描（仅读取变化的文件）',
            icon: const Icon(Icons.refresh),
            onPressed: state.isScanning || state.songs.isEmpty
                ? null
                : notifier.rescan,
          ),
          IconButton(
            tooltip: '选择文件夹',
            icon: const Icon(Icons.folder_open),
            onPressed: state.isScanning ? null : notifier.pickAndScanDirectory,
          ),
        ],
      ),
      body: Column(
        children: [
          _Header(state: state, notifier: notifier),
          if (state.isScanning) const LinearProgressIndicator(minHeight: 2),
          if (state.error != null) _ErrorBanner(message: state.error!),
          if (state.skippedFiles.isNotEmpty)
            _SkippedFilesBanner(files: state.skippedFiles),
          Expanded(
            child: state.songs.isEmpty && !state.isLoading
                ? _EmptyLocalMusic(isScanning: state.isScanning)
                : _LocalLibraryBody(state: state),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.notifier});

  final LocalMusicState state;
  final LocalMusicNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scan = state.lastScan;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  state.selectedDirectory ?? '尚未选择文件夹',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.colorScheme.outline, fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: state.isScanning
                    ? null
                    : notifier.pickAndScanDirectory,
                icon: const Icon(Icons.folder),
                label: const Text('选择文件夹'),
              ),
            ],
          ),
          if (scan != null) ...[
            const SizedBox(height: 6),
            Text(
              '共 ${scan.totalCount} 首 · 本次解析 ${scan.parsedCount} · '
              '复用 ${scan.reusedCount}'
              '${scan.removedCount > 0 ? ' · 移除 ${scan.removedCount}' : ''}'
              ' · ${scan.elapsed.inMilliseconds}ms',
              key: const Key('local-music-scan-summary'),
              style: TextStyle(color: theme.colorScheme.outline, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<LocalLibraryView>(
                    segments: const [
                      ButtonSegment(
                        value: LocalLibraryView.songs,
                        label: Text('歌曲'),
                        icon: Icon(Icons.music_note),
                      ),
                      ButtonSegment(
                        value: LocalLibraryView.albums,
                        label: Text('专辑'),
                        icon: Icon(Icons.album),
                      ),
                      ButtonSegment(
                        value: LocalLibraryView.artists,
                        label: Text('歌手'),
                        icon: Icon(Icons.person),
                      ),
                      ButtonSegment(
                        value: LocalLibraryView.folders,
                        label: Text('文件夹'),
                        icon: Icon(Icons.folder_copy),
                      ),
                    ],
                    selected: {state.view},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        notifier.setView(selection.first),
                  ),
                ),
              ),
            ],
          ),
          SwitchListTile(
            key: const Key('local-music-merge-switch'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: state.mergeWithOnline,
            title: const Text('与在线曲库去重', style: TextStyle(fontSize: 13)),
            subtitle: const Text(
              '同一首歌只显示一条（本地优先）',
              style: TextStyle(fontSize: 11),
            ),
            onChanged: (value) => notifier.setMergeWithOnline(value),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

/// H-16 noted `skippedFiles` was always empty, so the UI could never explain a
/// file it dropped. It now lists the lyric files that could not be decoded
/// (an encrypted KRC without a valid payload, a `.qrc` that is not QRC…).
class _SkippedFilesBanner extends StatelessWidget {
  const _SkippedFilesBanner({required this.files});

  final List<String> files;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        key: const Key('local-music-skipped-banner'),
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('已跳过 ${files.length} 个文件'),
            content: SizedBox(
              width: 420,
              child: ListView(
                shrinkWrap: true,
                children: [for (final file in files) Text(file)],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: theme.colorScheme.outline),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '已跳过 ${files.length} 个无法解析的歌词文件（点击查看）',
                style: TextStyle(
                  color: theme.colorScheme.outline,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalLibraryBody extends StatelessWidget {
  const _LocalLibraryBody({required this.state});

  final LocalMusicState state;

  @override
  Widget build(BuildContext context) {
    switch (state.view) {
      case LocalLibraryView.songs:
        return _SongList(state: state);
      case LocalLibraryView.albums:
        return _GroupList(
          groups: state.albumGroups,
          keyPrefix: 'album',
          emptyLabel: '没有可用的专辑信息',
        );
      case LocalLibraryView.artists:
        return _GroupList(
          groups: state.artistGroups,
          keyPrefix: 'artist',
          emptyLabel: '没有可用的歌手信息',
        );
      case LocalLibraryView.folders:
        return _GroupList(
          groups: state.folderGroups,
          keyPrefix: 'folder',
          emptyLabel: '没有可用的文件夹',
        );
    }
  }
}

class _SongList extends ConsumerWidget {
  const _SongList({required this.state});

  final LocalMusicState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = state.visibleSongs;
    // Built once for the whole list: a per-row `firstWhere` over the index
    // would be O(n²) on a 1000-track library.
    final tracksByPath = <String, LocalTrackEntry>{
      for (final track in state.tracks) track.path: track,
    };
    final onlineKeys = state.onlineKeys;
    return AppScrollbar(
      builder: (controller) => ListView.builder(
        controller: controller,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          final track = tracksByPath[song.id];
          return _SongTile(
            song: song,
            track: track,
            hasLyrics: state.lyricsBySongId.containsKey(song.id),
            alsoOnline: onlineKeys.contains(song.dedupeKey),
            onTap: () => ref
                .read(playerProvider.notifier)
                .playPlaylist(songs, startIndex: index),
          );
        },
      ),
    );
  }
}

class _GroupList extends ConsumerWidget {
  const _GroupList({
    required this.groups,
    required this.keyPrefix,
    required this.emptyLabel,
  });

  final List<LocalTrackGroup> groups;
  final String keyPrefix;
  final String emptyLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (groups.isEmpty) {
      return Center(
        child: Text(
          emptyLabel,
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }
    return AppScrollbar(
      builder: (controller) => ListView.builder(
        controller: controller,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: groups.length,
        itemBuilder: (context, index) {
          final group = groups[index];
          return ExpansionTile(
            key: Key('$keyPrefix-group-${group.id}'),
            leading: _Cover(path: group.coverPath),
            title: Text(group.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${group.subtitle ?? ''}'
              '${group.subtitle != null ? ' · ' : ''}'
              '${group.trackCount} 首',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            children: [
              for (var i = 0; i < group.tracks.length; i++)
                _SongTile(
                  song: group.tracks[i].toSong(),
                  track: group.tracks[i],
                  hasLyrics: false,
                  alsoOnline: false,
                  onTap: () => ref
                      .read(playerProvider.notifier)
                      .playPlaylist(
                        [for (final track in group.tracks) track.toSong()],
                        startIndex: i,
                      ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.song,
    required this.track,
    required this.hasLyrics,
    required this.alsoOnline,
    required this.onTap,
  });

  final Song song;
  final LocalTrackEntry? track;
  final bool hasLyrics;
  final bool alsoOnline;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = <String>[
      if (track?.artistName != null) track!.displayArtist,
      if (track?.albumName != null) track!.displayAlbum,
      if (hasLyrics) '已匹配歌词',
      if (alsoOnline) '在线曲库中也有',
    ];
    return ListTile(
      leading: _Cover(path: track?.coverPath),
      title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitleParts.isEmpty
            ? (track?.folderName ?? song.id)
            : subtitleParts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: theme.colorScheme.outline, fontSize: 12),
      ),
      trailing: track != null && track!.durationMs > 0
          ? Text(_formatDuration(track!.duration))
          : const Icon(Icons.play_arrow),
      onTap: onTap,
    );
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _Cover extends StatelessWidget {
  const _Cover({this.path});

  final String? path;

  static const double size = 40;

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    if (file == null || !file.existsSync()) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: const Icon(Icons.music_note),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => CircleAvatar(
          radius: size / 2,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.music_note),
        ),
      ),
    );
  }
}

class _EmptyLocalMusic extends StatelessWidget {
  final bool isScanning;

  const _EmptyLocalMusic({required this.isScanning});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_music_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              isScanning ? '正在扫描本地音乐' : '选择一个文件夹开始扫描本地音乐',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
