import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/share/song_actions.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../models/playlist.dart';
import '../../../../models/song.dart';
import '../../../library/presentation/providers/my_playlists_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../data/local_track_store.dart';
import '../../domain/local_library_grouping.dart';
import '../../domain/local_library_query.dart';
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
          if (state.songs.isNotEmpty)
            IconButton(
              key: const Key('local-music-select-toggle'),
              tooltip: state.selectionMode ? '退出多选' : '多选',
              icon: Icon(
                state.selectionMode
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
              ),
              onPressed: () => notifier.setSelectionMode(!state.selectionMode),
            ),
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
          // An inline notice, only while there is still a library behind it. With
          // nothing to show, the failure belongs in the full-page state below
          // (`AsyncStateView.error`), which also carries the retry affordance.
          if (state.error != null && state.songs.isNotEmpty)
            _ErrorBanner(message: state.error!),
          if (state.skippedFiles.isNotEmpty)
            _SkippedFilesBanner(files: state.skippedFiles),
          Expanded(
            child: _LocalLibraryBody(state: state, notifier: notifier),
          ),
          if (state.isSelecting) _SelectionBar(state: state, notifier: notifier),
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
          _SearchAndSortBar(state: state, notifier: notifier),
        ],
      ),
    );
  }
}

/// Search box, sort control and filter chips.
///
/// Stateful only because the keyword lives in a `TextEditingController`: the query
/// itself lives in the provider, so this widget never holds the truth — it syncs
/// the field when something *else* changes the keyword (the 清除 action, or a
/// future "jump to this artist" path) and never fights the user's typing.
class _SearchAndSortBar extends StatefulWidget {
  const _SearchAndSortBar({required this.state, required this.notifier});

  final LocalMusicState state;
  final LocalMusicNotifier notifier;

  @override
  State<_SearchAndSortBar> createState() => _SearchAndSortBarState();
}

class _SearchAndSortBarState extends State<_SearchAndSortBar> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.state.query.keyword,
  );

  @override
  void didUpdateWidget(covariant _SearchAndSortBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final keyword = widget.state.query.keyword;
    // Only when the *provider* changed it: otherwise this would reset the cursor
    // on every keystroke.
    if (keyword != oldWidget.state.query.keyword && keyword != _controller.text) {
      _controller.text = keyword;
      _controller.selection = TextSelection.collapsed(offset: keyword.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final query = state.query;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('local-music-search-field'),
          controller: _controller,
          textInputAction: TextInputAction.search,
          onChanged: widget.notifier.setKeyword,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 20),
            hintText: '搜索标题、歌手或专辑',
            border: const OutlineInputBorder(),
            suffixIcon: query.hasKeyword
                ? IconButton(
                    key: const Key('local-music-search-clear'),
                    tooltip: '清空搜索',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _controller.clear();
                      widget.notifier.setKeyword('');
                    },
                  )
                : null,
          ),
        ),
        Row(
          children: [
            PopupMenuButton<LocalSortField>(
              key: const Key('local-music-sort-button'),
              tooltip: '排序方式',
              onSelected: widget.notifier.setSort,
              itemBuilder: (context) => [
                for (final field in LocalSortField.values)
                  CheckedPopupMenuItem<LocalSortField>(
                    value: field,
                    checked: query.sort == field,
                    child: Text(field.label),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sort, size: 16),
                    const SizedBox(width: 4),
                    // The *button* deliberately does not print the selected field
                    // name: '歌手' and '专辑' are also the view switcher's labels,
                    // and a duplicate `Text` would make those assertions ambiguous
                    // (and the user would see the same word twice on one screen).
                    const Text('排序', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
            IconButton(
              key: const Key('local-music-sort-direction'),
              tooltip: query.descending ? '改为升序' : '改为降序',
              icon: Icon(
                query.descending ? Icons.arrow_downward : Icons.arrow_upward,
                size: 18,
              ),
              onPressed: widget.notifier.toggleSortDirection,
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final filter in LocalTrackFilter.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: FilterChip(
                          key: Key('local-music-filter-${filter.name}'),
                          label: Text(
                            filter.label,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: query.filters.contains(filter),
                          onSelected: (selected) =>
                              widget.notifier.toggleFilter(filter, selected),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (state.isQueryActive)
              TextButton(
                key: const Key('local-music-clear-query'),
                onPressed: () {
                  _controller.clear();
                  widget.notifier.clearQuery();
                },
                child: const Text('清除'),
              ),
          ],
        ),
        if (state.isQueryActive)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '筛选后 ${state.queriedTracks.length} / ${state.tracks.length} 首',
              key: const Key('local-music-filter-summary'),
              style: TextStyle(color: theme.colorScheme.outline, fontSize: 12),
            ),
          ),
      ],
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
  const _LocalLibraryBody({required this.state, required this.notifier});

  final LocalMusicState state;
  final LocalMusicNotifier notifier;

  @override
  Widget build(BuildContext context) {
    // The three states live in `AsyncStateView` so this page cannot drift from
    // the rest of the app (retry control, body colour, spinner style).
    if (state.isLoading) {
      return const AsyncStateView.loading(skeleton: true);
    }
    // A library that failed to load *and* has nothing to show: retry means
    // "read it again", which is the same walk `rescan` performs.
    if (state.error != null && state.songs.isEmpty) {
      return AsyncStateView.error(
        title: '本地曲库读取失败',
        message: state.error,
        onRetry: notifier.rescan,
      );
    }
    // Nothing in the index at all: never picked a folder, or the first scan is
    // still running. Not a failure, so no retry — the header owns that action.
    if (state.songs.isEmpty) {
      return AsyncStateView.empty(
        title: state.isScanning ? '正在扫描本地音乐' : '选择一个文件夹开始扫描本地音乐',
        message: state.isScanning
            ? '只读取变化的文件，已解析过的会直接复用'
            : '扫描后歌曲、专辑、歌手与文件夹视图都可以离线浏览',
        icon: Icons.library_music_outlined,
      );
    }
    // A query that matches nothing is its own state: the library is fine, the
    // filter is not — so this is an empty state, not an error.
    if (state.queriedTracks.isEmpty) {
      return AsyncStateView.empty(
        title: '没有匹配的歌曲',
        message: '试试清除搜索词或筛选条件',
        icon: Icons.search_off,
      );
    }
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
    final notifier = ref.read(localMusicProvider.notifier);
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
          final path = track?.path;
          // A row without a local index entry (an online song merged in) has no
          // path to tick, so it simply cannot be selected.
          final selectable = path != null;
          return _SongTile(
            song: song,
            track: track,
            hasLyrics: state.lyricsBySongId.containsKey(song.id),
            alsoOnline: onlineKeys.contains(song.dedupeKey),
            selecting: state.isSelecting,
            selected: selectable && state.selectedPaths.contains(path),
            onSelect: selectable ? () => notifier.toggleSelected(path) : null,
            onTap: state.isSelecting
                ? (selectable ? () => notifier.toggleSelected(path) : null)
                : () => ref
                      .read(playerProvider.notifier)
                      .playPlaylist(songs, startIndex: index),
            // The `_SongTile` itself is stateless (no `ref`), so the long-press
            // menu is built here and passed down. `isLocal: true` makes the
            // frozen sheet hide the actions a local file cannot do (下载/分享/
            // 加歌单/喜欢) — there is no platform id behind the track. While
            // selecting, the tap is the tick, so the sheet is suppressed for the
            // rows that can be ticked.
            onLongPress: state.isSelecting && selectable
                ? null
                : () => unawaited(
                    showSongActionsMenu(context, ref, song: song, isLocal: true),
                  ),
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
      return AsyncStateView.empty(
        title: emptyLabel,
        message: '换一个视图，或者重新扫描一次',
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
                  onLongPress: () {
                    final song = group.tracks[i].toSong();
                    unawaited(
                      showSongActionsMenu(
                        context,
                        ref,
                        song: song,
                        isLocal: true,
                      ),
                    );
                  },
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
    required this.onLongPress,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
  });

  final Song song;
  final LocalTrackEntry? track;
  final bool hasLyrics;
  final bool alsoOnline;

  /// Null while a batch action is in progress, or for a row that cannot be
  /// ticked (no local index entry) — a null callback is how a `ListTile` shows
  /// "this does nothing right now" without a disabled-looking custom button.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Whether the page is in multi-select mode; the row then leads with a checkbox
  /// **instead of** the cover, so the tile keeps its single-line height.
  final bool selecting;
  final bool selected;
  final VoidCallback? onSelect;

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
      leading: selecting
          ? Checkbox(
              key: Key('local-music-select-${track?.path ?? song.id}'),
              value: selected,
              onChanged: onSelect == null ? null : (_) => onSelect!(),
            )
          : _Cover(path: track?.coverPath),
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
      onTap: selecting ? onSelect : onTap,
      onLongPress: onLongPress,
    );
  }

  static String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Cache key for a cover file: the path **and** the library version.
///
/// The library version is the identity of the current scan result: a scan builds
/// a fresh [LocalMusicScanResult] (see `LocalMusicLocalMusicState.lastScan`), and
/// a rescan can rewrite or delete a cover at the same path — so the existence
/// answer must be recomputed then, not only when the path changes. It is an
/// `identityHashCode` rather than a timestamp because the scan result carries no
/// timestamp of its own (the per-row `scannedAt` would make the key O(n) to
/// compute for every row).
@immutable
class CoverFileKey {
  const CoverFileKey(this.path, this.libraryVersion);

  final String path;
  final int libraryVersion;

  @override
  bool operator ==(Object other) =>
      other is CoverFileKey &&
      other.path == path &&
      other.libraryVersion == libraryVersion;

  @override
  int get hashCode => Object.hash(path, libraryVersion);
}

/// The file-existence probe used for covers; injectable so a test can count the
/// stats (same shape as `fileExistsProbeProvider` in `app_background.dart`).
typedef FileExistsProbe = bool Function(String path);

final coverExistsProbeProvider = Provider<FileExistsProbe>(
  (ref) => (path) => File(path).existsSync(),
);

/// Memoised cover-file existence.
///
/// `_Cover` used to call `File(path).existsSync()` inside `build`, i.e. one
/// synchronous `stat` **per row per rebuild**: opening or scrolling a library of
/// a few hundred tracks meant hundreds of blocking stats on FUSE-mounted
/// external storage, on the frame that paints the list.
///
/// `autoDispose` because the key includes the scan generation: without it every
/// scan would leave one family entry per cover behind, for the container's whole
/// lifetime.
final coverFileExistsProvider = Provider.autoDispose.family<bool, CoverFileKey>((
  ref,
  key,
) {
  return ref.watch(coverExistsProbeProvider)(key.path);
});

class _Cover extends ConsumerWidget {
  const _Cover({this.path});

  final String? path;

  static const double size = 40;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imagePath = path;
    if (imagePath == null || imagePath.isEmpty) return _placeholder(context);

    final scan = ref.watch(localMusicProvider.select((s) => s.lastScan));
    final exists = ref.watch(
      coverFileExistsProvider(
        CoverFileKey(imagePath, identityHashCode(scan)),
      ),
    );
    if (!exists) return _placeholder(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(
        File(imagePath),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => _placeholder(context),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: const Icon(Icons.music_note),
    );
  }
}

/// The bottom bar shown while multi-select is on.
///
/// It is the page's only destructive affordance, and it routes through
/// [LocalMusicNotifier.removeSelected] — the single entry point that deletes
/// index records and cached lyrics and **never** touches an audio file. The
/// confirmation dialog says exactly that, because "移出曲库" has to be
/// distinguishable from "删除文件".
class _SelectionBar extends ConsumerWidget {
  const _SelectionBar({required this.state, required this.notifier});

  final LocalMusicState state;
  final LocalMusicNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hasSelection = state.selectedCount > 0;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              TextButton(
                key: const Key('local-music-selection-cancel'),
                onPressed: () => notifier.setSelectionMode(false),
                child: const Text('取消'),
              ),
              Expanded(
                child: Text(
                  '已选 ${state.selectedCount} 首',
                  key: const Key('local-music-selection-count'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                key: const Key('local-music-select-all'),
                onPressed: notifier.selectAllVisible,
                child: const Text('全选'),
              ),
              TextButton(
                key: const Key('local-music-batch-add'),
                onPressed: hasSelection
                    ? () => _addToPlaylist(context, ref)
                    : null,
                child: const Text('加歌单'),
              ),
              TextButton(
                key: const Key('local-music-batch-remove'),
                onPressed: hasSelection
                    ? () => _removeFromLibrary(context, ref)
                    : null,
                child: Text(
                  '移出曲库',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Adds every ticked track to a playlist the user picks.
  ///
  /// The playlists themselves belong to `features/library`, so this page drives
  /// that feature's notifier instead of duplicating its storage.
  Future<void> _addToPlaylist(BuildContext context, WidgetRef ref) async {
    final tracks = ref.read(localMusicProvider).selectedTracks;
    if (tracks.isEmpty) return;
    final playlists = ref.read(myPlaylistsProvider).playlists;
    if (playlists.isEmpty) {
      showInfoSnackBar(context, '还没有自建歌单，先在「我的歌单」里创建一个');
      return;
    }
    final target = await showModalBottomSheet<Playlist>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final playlist in playlists)
              ListTile(
                key: Key('local-music-pick-playlist-${playlist.id}'),
                leading: const Icon(Icons.queue_music),
                title: Text(playlist.name),
                onTap: () => Navigator.of(sheetContext).pop(playlist),
              ),
          ],
        ),
      ),
    );
    if (target == null) return;

    final playlistsNotifier = ref.read(myPlaylistsProvider.notifier);
    var added = 0;
    for (final track in tracks) {
      if (await playlistsNotifier.addSong(target.id, track.toSong())) added++;
    }
    notifier.clearSelection();
    if (!context.mounted) return;
    showSuccessSnackBar(context, '已把 $added 首加入「${target.name}」');
  }

  Future<void> _removeFromLibrary(BuildContext context, WidgetRef ref) async {
    final count = ref.read(localMusicProvider).selectedCount;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('移出 $count 首？'),
        content: const Text(
          '只会从曲库索引里移除这些记录及其缓存歌词，不会删除音频文件；下次扫描会重新出现。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('local-music-remove-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('移出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final removed = await notifier.removeSelected();
    if (!context.mounted) return;
    showInfoSnackBar(context, '已移出 $removed 首（音频文件未改动）');
  }
}
