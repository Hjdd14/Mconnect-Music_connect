import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/desktop/desktop_empty_state.dart';
import '../../../../core/desktop/desktop_page_scaffold.dart';
import '../../../../core/desktop/desktop_song_table.dart';
import '../../../../core/desktop/desktop_tokens.dart';
import '../../../../models/platform_type.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../data/local_track_store.dart';
import '../../domain/local_library_query.dart';
import '../providers/local_music_provider.dart';

/// 本地音乐桌面页。
///
/// The phone page is a [Scaffold] with an [AppBar], a bottom selection bar and a
/// [ListView] of [ListTile]s. None of that belongs in the desktop shell: the
/// shell already paints the navigation, the player bar and the rounded plate.
/// This page therefore keeps only what a desktop music manager needs — a
/// toolbar, the scan root, and a table.
///
/// The table header, the column geometry, the platform badge and the duration
/// formatter come from the shared desktop song-table kit, so this page lines up
/// pixel-for-pixel with the library/search/queue tables.
class LocalMusicDesktopPage extends ConsumerStatefulWidget {
  const LocalMusicDesktopPage({super.key});

  @override
  ConsumerState<LocalMusicDesktopPage> createState() =>
      _LocalMusicDesktopPageState();
}

class _LocalMusicDesktopPageState extends ConsumerState<LocalMusicDesktopPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(localMusicProvider);
    final notifier = ref.read(localMusicProvider.notifier);
    final currentSongId = ref.watch(
      playerProvider.select((player) => player.currentSong?.id),
    );

    // The provider owns the keyword (it is part of the immutable query), so a
    // "清除筛选" — or a state restored from the database — has to flow back into
    // the text field. Comparing first prevents fighting the user's typing.
    ref.listen(localMusicProvider.select((value) => value.query.keyword), (
      previous,
      next,
    ) {
      if (_searchController.text == next) return;
      _searchController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    });

    final tracks = state.queriedTracks;

    return DesktopPageScaffold(
      title: '本地音乐',
      subtitle: '共 ${state.tracks.length} 首 · 桌面表格视图',
      actions: [
        IconButton(
          tooltip: '重新扫描（仅读取变化的文件）',
          onPressed: state.isScanning
              ? null
              : () => unawaited(notifier.rescan()),
          icon: const Icon(Icons.refresh, size: 20),
        ),
        FilledButton.icon(
          onPressed: state.isScanning
              ? null
              : () => unawaited(notifier.pickAndScanDirectory()),
          icon: const Icon(Icons.folder_open, size: 18),
          label: const Text('选择文件夹'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LibraryInfoBar(state: state),
          const SizedBox(height: DesktopSpacing.sm),
          _QueryBar(
            state: state,
            notifier: notifier,
            controller: _searchController,
          ),
          if (state.isScanning)
            const Padding(
              padding: EdgeInsets.only(top: DesktopSpacing.sm),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (state.error != null && state.tracks.isNotEmpty)
            _InlineNotice(
              message: state.error!,
              icon: Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
          const SizedBox(height: DesktopSpacing.md),
          Expanded(
            child: _buildBody(context, state, tracks, currentSongId, notifier),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    LocalMusicState state,
    List<LocalTrackEntry> tracks,
    String? currentSongId,
    LocalMusicNotifier notifier,
  ) {
    if (state.isLoading && state.tracks.isEmpty) {
      return const DesktopInlineLoading(label: '正在读取本地曲库');
    }
    if (state.error != null && state.tracks.isEmpty) {
      return DesktopInlineError(
        message: state.error!,
        onRetry: () => unawaited(notifier.loadFromIndex()),
      );
    }
    if (state.tracks.isEmpty) {
      return DesktopEmptyState(
        icon: Icons.folder_open_outlined,
        title: '还没有本地音乐',
        message: '选择一个文件夹，Mconnect 会读取其中的音频文件与同名歌词',
        action: FilledButton.icon(
          onPressed: () => unawaited(notifier.pickAndScanDirectory()),
          icon: const Icon(Icons.folder_open, size: 18),
          label: const Text('选择文件夹'),
        ),
      );
    }
    if (tracks.isEmpty) {
      return DesktopEmptyState(
        icon: Icons.search_off,
        title: '没有匹配的歌曲',
        message: '换一个关键词，或者清除当前的筛选条件',
        action: OutlinedButton(
          onPressed: notifier.clearQuery,
          child: const Text('清除筛选'),
        ),
      );
    }
    return _TrackTable(
      tracks: tracks,
      state: state,
      currentSongId: currentSongId,
      onSort: (key) => _handleHeaderSort(key, state, notifier),
      onPlay: (index) {
        final songs = [for (final track in tracks) track.toSong()];
        unawaited(
          ref
              .read(playerProvider.notifier)
              .playPlaylist(songs, startIndex: index),
        );
      },
    );
  }

  /// The shared header reports a [DesktopSongColumn] key. Two of the page's
  /// sort fields (最近添加 / 播放次数) have no column, so they are only reachable
  /// from the toolbar dropdown.
  void _handleHeaderSort(
    String key,
    LocalMusicState state,
    LocalMusicNotifier notifier,
  ) {
    final field = switch (key) {
      DesktopSongColumn.artist => LocalSortField.artist,
      DesktopSongColumn.album => LocalSortField.album,
      DesktopSongColumn.duration => LocalSortField.duration,
      _ => LocalSortField.title,
    };
    if (state.query.sort == field) {
      notifier.toggleSortDirection();
    } else {
      notifier.setSort(field);
    }
  }
}

class _LibraryInfoBar extends StatelessWidget {
  const _LibraryInfoBar({required this.state});

  final LocalMusicState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final directory = state.selectedDirectory;
    final scan = state.lastScan;
    final meta = <String>[
      '共 ${state.tracks.length} 首',
      if (scan != null) '本次解析 ${scan.parsedCount}',
      if (scan != null) '复用 ${scan.reusedCount}',
      if (state.skippedFiles.isNotEmpty) '跳过 ${state.skippedFiles.length} 个文件',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesktopSpacing.md,
        vertical: DesktopSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
        borderRadius: DesktopRadii.mdAll,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: DesktopSpacing.sm),
          Expanded(
            child: Text(
              directory == null || directory.isEmpty ? '尚未选择扫描文件夹' : directory,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DesktopText.caption.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: DesktopSpacing.md),
          Text(
            meta.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DesktopText.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _QueryBar extends StatelessWidget {
  const _QueryBar({
    required this.state,
    required this.notifier,
    required this.controller,
  });

  final LocalMusicState state;
  final LocalMusicNotifier notifier;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = state.query;
    return Row(
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            key: const Key('local-desktop-search-field'),
            controller: controller,
            onChanged: notifier.setKeyword,
            style: DesktopText.body.copyWith(color: scheme.onSurface),
            decoration: InputDecoration(
              isDense: true,
              hintText: '搜索标题、歌手或专辑',
              hintStyle: DesktopText.body.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              prefixIcon: const Icon(Icons.search, size: 18),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: DesktopSpacing.md,
                vertical: DesktopSpacing.sm,
              ),
              filled: true,
              fillColor: scheme.surfaceContainerLow,
              border: const OutlineInputBorder(
                borderRadius: DesktopRadii.mdAll,
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: DesktopRadii.mdAll,
                borderSide: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: DesktopRadii.mdAll,
                borderSide: BorderSide(color: scheme.primary, width: 1.4),
              ),
            ),
          ),
        ),
        const SizedBox(width: DesktopSpacing.sm),
        Container(
          height: 40,
          padding: const EdgeInsets.only(
            left: DesktopSpacing.md,
            right: DesktopSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: DesktopRadii.mdAll,
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<LocalSortField>(
              value: query.sort,
              isDense: true,
              borderRadius: DesktopRadii.mdAll,
              style: DesktopText.body.copyWith(color: scheme.onSurface),
              icon: Icon(
                Icons.unfold_more,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              items: [
                for (final field in LocalSortField.values)
                  DropdownMenuItem<LocalSortField>(
                    value: field,
                    child: Text(field.label),
                  ),
              ],
              onChanged: (field) {
                if (field != null) notifier.setSort(field);
              },
            ),
          ),
        ),
        const SizedBox(width: DesktopSpacing.xs),
        IconButton(
          tooltip: query.descending ? '当前降序，点击切换' : '当前升序，点击切换',
          onPressed: notifier.toggleSortDirection,
          icon: Icon(
            query.descending ? Icons.arrow_downward : Icons.arrow_upward,
            size: 18,
          ),
        ),
        const SizedBox(width: DesktopSpacing.sm),
        Expanded(
          child: Wrap(
            spacing: DesktopSpacing.sm,
            runSpacing: DesktopSpacing.xs,
            children: [
              for (final filter in LocalTrackFilter.values)
                FilterChip(
                  key: Key('local-desktop-filter-${filter.name}'),
                  label: Text(filter.label),
                  selected: query.filters.contains(filter),
                  onSelected: (enabled) =>
                      notifier.toggleFilter(filter, enabled),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
        ),
        if (state.isQueryActive)
          TextButton(onPressed: notifier.clearQuery, child: const Text('清除筛选')),
      ],
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.message,
    required this.icon,
    required this.color,
  });

  final String message;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: DesktopSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: DesktopSpacing.sm),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DesktopText.caption.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackTable extends StatelessWidget {
  const _TrackTable({
    required this.tracks,
    required this.state,
    required this.currentSongId,
    required this.onSort,
    required this.onPlay,
  });

  final List<LocalTrackEntry> tracks;
  final LocalMusicState state;
  final String? currentSongId;
  final void Function(String key) onSort;
  final ValueChanged<int> onPlay;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showAlbum =
            constraints.maxWidth >= DesktopSongTableMetrics.albumBreakpoint;
        final sortKey = switch (state.query.sort) {
          LocalSortField.artist => DesktopSongColumn.artist,
          LocalSortField.album => DesktopSongColumn.album,
          LocalSortField.duration => DesktopSongColumn.duration,
          LocalSortField.title => DesktopSongColumn.title,
          LocalSortField.recentlyAdded || LocalSortField.playCount => null,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopSongTableHeader(
              showAlbum: showAlbum,
              sortKey: sortKey,
              sortAscending: !state.query.descending,
              onSort: onSort,
              actionsLabel: '播放',
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  vertical: DesktopSpacing.xs,
                ),
                itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  return _LocalTrackRow(
                    key: ValueKey(track.path),
                    track: track,
                    index: index,
                    showAlbum: showAlbum,
                    isCurrent: currentSongId == track.path,
                    onPlay: () => onPlay(index),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One local-library row.
///
/// The shared [DesktopSongRow] renders a [Song] and therefore its cover must be
/// a URL; a local track's cover is a file on disk (the scanner deliberately does
/// not put it in Song.coverUrl, which every remote cover consumer treats as a
/// network image). The columns are the shared ones — same metrics, same header —
/// so the only thing this row changes is where the thumbnail comes from.
class _LocalTrackRow extends StatefulWidget {
  const _LocalTrackRow({
    super.key,
    required this.track,
    required this.index,
    required this.showAlbum,
    required this.isCurrent,
    required this.onPlay,
  });

  final LocalTrackEntry track;
  final int index;
  final bool showAlbum;
  final bool isCurrent;
  final VoidCallback onPlay;

  @override
  State<_LocalTrackRow> createState() => _LocalTrackRowState();
}

class _LocalTrackRowState extends State<_LocalTrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final track = widget.track;
    return MouseRegion(
      onEnter: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: Material(
        color: widget.isCurrent
            ? scheme.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: DesktopRadii.smAll,
        child: InkWell(
          onTap: widget.onPlay,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: DesktopRadii.smAll,
          hoverColor: scheme.onSurface.withValues(alpha: 0.05),
          child: SizedBox(
            height: DesktopSongTableMetrics.rowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesktopSongTableMetrics.horizontalPadding,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: DesktopSongTableMetrics.indexWidth,
                    child: Center(child: _indexBadge(scheme)),
                  ),
                  const SizedBox(width: DesktopSpacing.sm),
                  SizedBox(
                    width: DesktopSongTableMetrics.coverSize,
                    height: DesktopSongTableMetrics.coverSize,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _LocalCover(path: track.coverPath),
                    ),
                  ),
                  const SizedBox(width: DesktopSpacing.md),
                  Expanded(
                    flex: 4,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopText.bodyStrong.copyWith(
                            color: widget.isCurrent
                                ? scheme.primary
                                : scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          track.displayArtist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DesktopText.caption.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.showAlbum) ...[
                    const SizedBox(width: DesktopSpacing.md),
                    Expanded(
                      flex: 3,
                      child: Text(
                        track.displayAlbum,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DesktopText.caption.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: DesktopSpacing.sm),
                  SizedBox(
                    width: DesktopSongTableMetrics.platformWidth,
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: DesktopPlatformBadge(platform: PlatformType.local),
                    ),
                  ),
                  SizedBox(
                    width: DesktopSongTableMetrics.durationWidth,
                    child: Text(
                      formatDesktopDuration(track.duration),
                      textAlign: TextAlign.right,
                      style: DesktopText.caption.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: DesktopSongTableMetrics.actionsWidth,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: '播放',
                          onPressed: widget.onPlay,
                          icon: const Icon(Icons.play_arrow, size: 18),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _indexBadge(ColorScheme scheme) {
    if (widget.isCurrent) {
      return Icon(Icons.graphic_eq, size: 16, color: scheme.primary);
    }
    if (_hovered) {
      return Icon(Icons.play_arrow, size: 18, color: scheme.onSurface);
    }
    return Text(
      '${widget.index + 1}',
      style: DesktopText.caption.copyWith(color: scheme.onSurfaceVariant),
    );
  }
}

/// Local covers are files on disk, not URLs: the shared [DesktopCoverArt] goes
/// through CachedNetworkImage, which cannot render a Windows path. A row without
/// a cover keeps the same slot so columns still line up.
class _LocalCover extends StatelessWidget {
  const _LocalCover({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.music_note, size: 16, color: scheme.onSurfaceVariant),
    );
    final value = path;
    if (value == null || value.isEmpty) return fallback;
    return Image.file(
      File(value),
      fit: BoxFit.cover,
      cacheWidth: 72,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}
