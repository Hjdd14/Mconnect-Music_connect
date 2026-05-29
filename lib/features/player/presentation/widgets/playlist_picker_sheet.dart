import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../models/playlist.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';
import '../../../../platform/base/platform_registry.dart';
import '../../../library/presentation/providers/my_playlists_provider.dart';

class PlaylistPickerSheet extends ConsumerStatefulWidget {
  final Song song;
  final Duration operationTimeout;

  const PlaylistPickerSheet({
    super.key,
    required this.song,
    this.operationTimeout = const Duration(seconds: 8),
  });

  @override
  ConsumerState<PlaylistPickerSheet> createState() =>
      _PlaylistPickerSheetState();
}

class _PlaylistPickerSheetState extends ConsumerState<PlaylistPickerSheet> {
  late Future<List<Playlist>> _playlistsFuture;
  bool _isAdding = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _playlistsFuture = _loadPlaylists();
  }

  Future<List<Playlist>> _loadPlaylists() async {
    List<Playlist> myPlaylists = const [];
    try {
      await ref.read(myPlaylistsProvider.notifier).load();
      myPlaylists = ref.read(myPlaylistsProvider).playlists;
    } catch (_) {
      myPlaylists = const [];
    }
    if (widget.song.platform == PlatformType.local) {
      return myPlaylists;
    }
    try {
      final platform = PlatformRegistry.get(widget.song.platform);
      if (!platform.isLoggedIn) return myPlaylists;
      final platformPlaylists = await platform.getUserPlaylists().timeout(
        widget.operationTimeout,
      );
      return [...myPlaylists, ...platformPlaylists];
    } catch (_) {
      if (myPlaylists.isNotEmpty) return myPlaylists;
      rethrow;
    }
  }

  Future<void> _addToPlaylist(Playlist playlist) async {
    if (_isAdding) return;
    setState(() {
      _isAdding = true;
      _actionError = null;
    });

    try {
      final bool ok;
      if (playlist.platform == PlatformType.local) {
        ok = await ref
            .read(myPlaylistsProvider.notifier)
            .addSong(playlist.id, widget.song)
            .timeout(widget.operationTimeout);
      } else {
        final platform = PlatformRegistry.get(widget.song.platform);
        ok = await platform
            .addSongToPlaylist(playlist.editableId, widget.song)
            .timeout(widget.operationTimeout);
      }
      if (!mounted) return;
      Navigator.pop(context, ok);
    } on TimeoutException {
      _showActionFailure();
    } catch (_) {
      _showActionFailure();
    }
  }

  void _showActionFailure() {
    if (!mounted) return;
    setState(() {
      _isAdding = false;
      _actionError = '添加失败或请求超时，请重试';
    });
  }

  void _retryLoad() {
    setState(() {
      _actionError = null;
      _playlistsFuture = _loadPlaylists();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: FutureBuilder<List<Playlist>>(
          future: _playlistsFuture,
          builder: (context, snapshot) {
            final playlists = snapshot.data ?? const <Playlist>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_add),
                  title: const Text('添加到歌单'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                if (_actionError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    child: Text(
                      _actionError!,
                      style: TextStyle(color: cs.error, fontSize: 13),
                    ),
                  ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (snapshot.hasError)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('加载歌单失败', style: TextStyle(color: cs.error)),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _retryLoad,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '暂无可编辑歌单，或当前平台暂不支持',
                      style: TextStyle(color: cs.outline),
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
                            enabled: !_isAdding,
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
                            trailing: _isAdding
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : null,
                            onTap: _isAdding
                                ? null
                                : () => _addToPlaylist(playlist),
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
