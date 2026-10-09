import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/share/song_actions.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../models/audio_quality.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/playlist.dart';
import '../../../../models/song.dart';
import '../../../../platform/base/platform_registry.dart';
import '../../../../l10n/l10n.dart';
import '../../../download/presentation/providers/download_provider.dart';
import '../../../download/presentation/widgets/download_button.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../providers/my_playlists_provider.dart';

/// A playlist's songs, plus the interaction layer on top: long-press to select,
/// batch actions, drag-to-reorder for 自建歌单, and the shared song action menu.
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
  List<Song>? _songs;
  Object? _error;
  bool _loading = true;

  bool _selectionMode = false;
  final Set<String> _selectedKeys = <String>{};
  bool _busy = false;

  /// Only 自建歌单 can be reordered: a platform playlist's order belongs to the
  /// platform, and there is no API to push an order back to it.
  bool get _isLocalPlaylist => widget.platform == PlatformType.local;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<List<Song>> _fetchSongs() {
    if (_isLocalPlaylist) {
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

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final songs = await _fetchSongs();
      if (!mounted) return;
      setState(() {
        _songs = songs;
        _error = null;
        _loading = false;
        // Drop selections whose song is gone (e.g. after a batch removal).
        _selectedKeys.removeWhere(
          (key) => !songs.any((song) => _keyOf(song) == key),
        );
        if (_selectedKeys.isEmpty) _selectionMode = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  String _keyOf(Song song) => '${song.platform.name}:${song.id}';

  List<Song> get _songsOrEmpty => _songs ?? const <Song>[];

  List<Song> get _selectedSongs => _songsOrEmpty
      .where((song) => _selectedKeys.contains(_keyOf(song)))
      .toList();

  void _enterSelection([Song? seed]) {
    setState(() {
      _selectionMode = true;
      if (seed != null) _selectedKeys.add(_keyOf(seed));
    });
  }

  void _toggleSelection(Song song) {
    setState(() {
      final key = _keyOf(song);
      if (!_selectedKeys.remove(key)) _selectedKeys.add(key);
      if (_selectedKeys.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedKeys.clear();
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedKeys.length == _songsOrEmpty.length) {
        _selectedKeys.clear();
        _selectionMode = false;
      } else {
        _selectedKeys
          ..clear()
          ..addAll(_songsOrEmpty.map(_keyOf));
      }
    });
  }

  void _playSongs(List<Song> songs, int index) {
    if (songs.isEmpty) return;
    unawaited(
      ref.read(playerProvider.notifier).playPlaylist(songs, startIndex: index),
    );
  }

  Future<void> _openSongMenu(Song song) async {
    // The menu owns "what each action does"; this page only supplies the
    // context and whether the row is a local file. No reload afterwards: none of
    // the actions can change *this* playlist, and refetching a platform playlist
    // on every menu dismissal would be a surprising network call.
    await showSongActionsMenu(
      context,
      ref,
      song: song,
      isLocal: song.platform == PlatformType.local,
    );
  }

  // --- batch actions -------------------------------------------------------

  Future<void> _batchDownload() async {
    final songs = _selectedSongs;
    if (songs.isEmpty || _busy) return;
    setState(() => _busy = true);

    final notifier = ref.read(downloadProvider.notifier);
    var queued = 0;
    for (final song in songs) {
      try {
        // Standard quality: a batch has no room for a per-song quality prompt,
        // and each row's download button still offers the full picker.
        await notifier.startDownload(song, AudioLevel.low);
        queued++;
      } catch (_) {
        // One song failing must not stop the batch.
      }
    }

    if (!mounted) return;
    setState(() => _busy = false);
    _exitSelection();
    if (queued == songs.length) {
      showSuccessSnackBar(context, '已按标准音质加入下载队列：$queued 首');
    } else {
      showErrorSnackBar(context, '已加入 $queued/${songs.length} 首，其余失败');
    }
  }

  Future<void> _batchAddToPlaylist() async {
    final songs = _selectedSongs;
    if (songs.isEmpty || _busy) return;

    final target = await showModalBottomSheet<Playlist>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _PlaylistTargetSheet(
        platform: widget.platform,
        songCount: songs.length,
      ),
    );
    if (target == null || !mounted) return;

    setState(() => _busy = true);
    final notifier = ref.read(myPlaylistsProvider.notifier);
    var added = 0;
    for (final song in songs) {
      try {
        final bool ok;
        if (target.platform == PlatformType.local) {
          ok = await notifier.addSong(target.id, song);
        } else {
          // The TARGET playlist's platform, not the song's. A song from one
          // platform may be added to a playlist on another, and each platform has
          // its own write endpoint; using `song.platform` sent the request to the
          // wrong platform with a playlist id it does not recognise.
          ok = await PlatformRegistry.get(target.platform)
              .addSongToPlaylist(target.editableId, song);
        }
        if (ok) added++;
      } catch (_) {
        // Keep going; the summary reports the shortfall.
      }
    }

    if (!mounted) return;
    setState(() => _busy = false);
    _exitSelection();
    if (added == songs.length) {
      showSuccessSnackBar(context, '已添加 $added 首到「${target.name}」');
    } else {
      showErrorSnackBar(
        context,
        '已添加 $added/${songs.length} 首到「${target.name}」，其余失败',
      );
    }
  }

  Future<void> _batchRemove() async {
    final songs = _selectedSongs;
    if (songs.isEmpty || _busy) return;
    setState(() => _busy = true);

    // Route by the PLAYLIST's platform. This used to always go through the local
    // repository, so removing a song from a platform playlist never reached the
    // platform at all — the request was written to a local playlist id that does
    // not exist there, and the UI reported a failure (or worse, looked like it
    // worked and came back on the next load).
    final bool isLocal = widget.platform == PlatformType.local;
    final notifier = ref.read(myPlaylistsProvider.notifier);
    final platform = isLocal ? null : PlatformRegistry.get(widget.platform);

    var removed = 0;
    for (final song in songs) {
      final bool ok;
      if (isLocal) {
        ok = await notifier.removeSong(widget.playlistId, song);
      } else {
        ok = await platform!
            .removeSongFromPlaylist(widget.playlistId, song)
            .timeout(const Duration(seconds: 8), onTimeout: () => false);
      }
      if (ok) removed++;
    }

    if (!mounted) return;
    setState(() => _busy = false);
    _exitSelection();
    await _load();
    if (!mounted) return;
    if (removed == songs.length) {
      showInfoSnackBar(context, '已从歌单移除 $removed 首');
    } else if (removed == 0 && !isLocal) {
      // Distinguish "the platform refused / does not support this" from a partial
      // failure: on a platform playlist a total failure most often means the
      // platform has no such operation, and claiming otherwise would be a lie.
      showErrorSnackBar(context, context.l10n.libraryRemoveUnsupported);
    } else {
      showErrorSnackBar(context, '已移除 $removed/${songs.length} 首，其余失败');
    }
  }

  Future<void> _onReorder(List<Song> songs, int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;

    final reordered = List<Song>.from(songs);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    // Optimistic: the row already moved on screen, so keep the model in step
    // and roll back from disk if the write fails.
    setState(() => _songs = reordered);

    final ok = await ref
        .read(myPlaylistsProvider.notifier)
        .reorderSongs(widget.playlistId, reordered);
    if (!mounted) return;
    if (!ok) {
      showErrorSnackBar(context, '保存歌单顺序失败，已恢复原顺序');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final songs = _songsOrEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: '退出多选',
                onPressed: _exitSelection,
              )
            : null,
        title: Text(_selectionMode ? '已选 ${_selectedKeys.length} 首' : '歌单详情'),
        actions: _selectionMode
            ? _selectionActions(songs)
            : [
                if (songs.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.checklist),
                    tooltip: '多选',
                    onPressed: () => _enterSelection(),
                  ),
              ],
      ),
      body: _buildBody(songs),
    );
  }

  List<Widget> _selectionActions(List<Song> songs) {
    final allSelected =
        songs.isNotEmpty && _selectedKeys.length == songs.length;
    return [
      IconButton(
        icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
        tooltip: allSelected ? '取消全选' : '全选',
        onPressed: _busy ? null : _toggleSelectAll,
      ),
      IconButton(
        icon: const Icon(Icons.download_outlined),
        tooltip: '批量下载',
        onPressed: _busy || _selectedKeys.isEmpty
            ? null
            : () => unawaited(_batchDownload()),
      ),
      IconButton(
        icon: const Icon(Icons.playlist_add),
        tooltip: '批量加入歌单',
        onPressed: _busy || _selectedKeys.isEmpty
            ? null
            : () => unawaited(_batchAddToPlaylist()),
      ),
      if (_isLocalPlaylist)
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          tooltip: '批量移出',
          onPressed: _busy || _selectedKeys.isEmpty
              ? null
              : () => unawaited(_batchRemove()),
        ),
    ];
  }

  Widget _buildBody(List<Song> songs) {
    if (_loading) {
      return const AsyncStateView.loading();
    }
    if (_error != null) {
      // No `message`: `_error` is whatever `_fetchSongs` threw (often a
      // `TimeoutException`), and the page has always shown the plain headline
      // rather than a raw exception to the user.
      return AsyncStateView.error(
        title: '加载歌单失败',
        onRetry: () => unawaited(_load()),
      );
    }
    if (songs.isEmpty) {
      return const AsyncStateView.empty(title: '歌单暂无歌曲');
    }

    return AppScrollbar(
      builder: (controller) {
        // Drag-to-reorder only where it can be persisted, and never while the
        // rows are checkboxes (dragging a selected row is ambiguous).
        if (_isLocalPlaylist && !_selectionMode) {
          return ReorderableListView.builder(
            scrollController: controller,
            header: _header(songs),
            buildDefaultDragHandles: false,
            itemCount: songs.length,
            proxyDecorator: (child, index, animation) =>
                Material(elevation: 4, color: Colors.transparent, child: child),
            // `onReorderItem` (not the deprecated `onReorder`): it already
            // adjusts `newIndex` for the item that was removed at `oldIndex`,
            // so [_onReorder] must not apply the classic `-1` correction again.
            onReorderItem: (oldIndex, newIndex) =>
                unawaited(_onReorder(songs, oldIndex, newIndex)),
            itemBuilder: (context, index) => _songTile(
              songs[index],
              index,
              key: ValueKey('reorder-${_keyOf(songs[index])}-$index'),
              dragHandleIndex: index,
            ),
          );
        }
        return ListView.builder(
          controller: controller,
          // +1 keeps the header in the same place in both modes.
          itemCount: songs.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) return _header(songs);
            final songIndex = index - 1;
            return _songTile(songs[songIndex], songIndex);
          },
        );
      },
    );
  }

  Widget _header(List<Song> songs) {
    return _PlaylistHeader(
      platform: widget.platform,
      name: widget.playlistName,
      coverUrl:
          widget.coverUrl ?? (songs.isNotEmpty ? songs.first.coverUrl : null),
      songCount: songs.length,
      isLoading: false,
      onPlayAll: songs.isEmpty ? null : () => _playSongs(songs, 0),
    );
  }

  Widget _songTile(Song song, int index, {Key? key, int? dragHandleIndex}) {
    final cs = Theme.of(context).colorScheme;
    final selected = _selectedKeys.contains(_keyOf(song));

    return ListTile(
      key: key ?? ValueKey(_keyOf(song)),
      selected: _selectionMode && selected,
      selectedTileColor: cs.primaryContainer.withValues(alpha: 0.4),
      leading: SizedBox(
        width: 40,
        child: Center(
          child: _selectionMode
              ? Checkbox(
                  value: selected,
                  onChanged: (_) => _toggleSelection(song),
                )
              : dragHandleIndex != null
              ? ReorderableDragStartListener(
                  index: dragHandleIndex,
                  child: Icon(
                    Icons.drag_handle,
                    size: 20,
                    color: cs.outline,
                    semanticLabel: '拖动排序',
                  ),
                )
              : Text(
                  '${index + 1}',
                  style: TextStyle(color: cs.outline, fontSize: 13),
                ),
        ),
      ),
      title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        song.artistNames,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: cs.outline, fontSize: 13),
      ),
      trailing: _selectionMode
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (song.platform != PlatformType.local)
                  DownloadButton(song: song, size: 22),
                IconButton(
                  icon: const Icon(Icons.more_vert, size: 20),
                  tooltip: '歌曲操作',
                  onPressed: () => unawaited(_openSongMenu(song)),
                ),
              ],
            ),
      onTap: _selectionMode
          ? () => _toggleSelection(song)
          : () => _playSongs(_songsOrEmpty, index),
      // Long-press selects; the action menu lives on the ⋮ button, so the two
      // gestures stay unambiguous.
      onLongPress: _selectionMode ? null : () => _enterSelection(song),
    );
  }
}

/// Picks the playlist a batch should be added to: this app's own playlists
/// always, plus the current platform's when the account is signed in.
class _PlaylistTargetSheet extends ConsumerStatefulWidget {
  const _PlaylistTargetSheet({required this.platform, required this.songCount});

  final PlatformType platform;
  final int songCount;

  @override
  ConsumerState<_PlaylistTargetSheet> createState() =>
      _PlaylistTargetSheetState();
}

class _PlaylistTargetSheetState extends ConsumerState<_PlaylistTargetSheet> {
  late final Future<List<Playlist>> _remoteFuture = _loadRemotePlaylists();

  /// The platform's own playlists, when the account is signed in.
  ///
  /// The app's own playlists are **watched** from the provider state instead of
  /// being fetched here: `MyPlaylistsNotifier.load()` mutates the provider, and
  /// Riverpod forbids a provider mutation while the widget tree is building —
  /// which is exactly when `initState` runs.
  Future<List<Playlist>> _loadRemotePlaylists() async {
    if (widget.platform == PlatformType.local) return const <Playlist>[];
    try {
      final platform = PlatformRegistry.get(widget.platform);
      if (!platform.isLoggedIn) return const <Playlist>[];
      return await platform.getUserPlaylists().timeout(
        const Duration(seconds: 8),
      );
    } catch (_) {
      return const <Playlist>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(myPlaylistsProvider).playlists;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: FutureBuilder<List<Playlist>>(
          future: _remoteFuture,
          builder: (context, snapshot) {
            final playlists = <Playlist>[...local, ...?snapshot.data];
            final stillLoading =
                playlists.isEmpty &&
                snapshot.connectionState == ConnectionState.waiting;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.playlist_add),
                  title: Text('把 ${widget.songCount} 首加入歌单'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                if (stillLoading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (playlists.isEmpty)
                  // 空态走共享视图：原来的 `Text(style: color: outline)` 正是
                  // 契约点名的「用边框色当正文色」问题（M-73）。高度固定，
                  // 因为这是底部弹窗里的区块空态，不该撑满 70% 的弹窗。
                  const SizedBox(
                    height: 180,
                    child: AsyncStateView.empty(
                      title: '暂无可编辑歌单，或当前平台暂不支持',
                    ),
                  )
                else
                  Flexible(
                    child: AppScrollbar(
                      builder: (controller) => ListView.builder(
                        controller: controller,
                        shrinkWrap: playlists.length < 6,
                        itemCount: playlists.length,
                        itemBuilder: (context, index) {
                          final playlist = playlists[index];
                          return ListTile(
                            leading: const Icon(Icons.queue_music),
                            title: Text(
                              playlist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              playlist.platform == PlatformType.local
                                  ? '我的歌单 · ${playlist.songCount} 首'
                                  : '${playlist.platform.displayName} · ${playlist.songCount} 首',
                            ),
                            onTap: () => Navigator.of(context).pop(playlist),
                          );
                        },
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
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
                    placeholder: (_, _) =>
                        _CoverPlaceholder(color: cs.primaryContainer),
                    errorWidget: (_, _, _) =>
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
