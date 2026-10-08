import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/share/share_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/transfer/playlist_export.dart';
import '../../../../core/transfer/transfer_format.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../core/widgets/async_state_view.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/playlist.dart';
import '../../../../models/song.dart';
import '../providers/my_playlists_provider.dart';
import '../providers/platform_playlists_provider.dart';

class PlatformPlaylistsPage extends ConsumerStatefulWidget {
  const PlatformPlaylistsPage({super.key});

  @override
  ConsumerState<PlatformPlaylistsPage> createState() =>
      _PlatformPlaylistsPageState();
}

class _PlatformPlaylistsPageState extends ConsumerState<PlatformPlaylistsPage>
    with SingleTickerProviderStateMixin {
  static const _tabs = [PlatformType.local, ...PlatformType.musicServices];
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(platformPlaylistsProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _createPlaylist() async {
    final platform = _tabs[_tabController.index];
    if (platform == PlatformType.local) {
      await _createMyPlaylist();
      return;
    }
    final state = ref.read(platformPlaylistsProvider);
    if (state.isCreatingFor(platform)) return;

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '歌单名称'),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('新建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final playlist = await ref
        .read(platformPlaylistsProvider.notifier)
        .create(platform, name);
    if (!mounted) return;
    showInfoSnackBar(context, playlist == null ? '新建歌单失败' : '已新建歌单');
  }

  Future<void> _createMyPlaylist() async {
    final state = ref.read(myPlaylistsProvider);
    if (state.isSaving) return;

    final name = await _askPlaylistName();
    if (name == null || name.isEmpty) return;

    final playlist = await ref.read(myPlaylistsProvider.notifier).create(name);
    if (!mounted) return;
    showInfoSnackBar(context, playlist == null ? '新建歌单失败' : '已新建歌单');
  }

  Future<String?> _askPlaylistName() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '歌单名称'),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('新建'),
          ),
        ],
      ),
    );
    controller.dispose();
    return name;
  }

  String _playlistRoute(Playlist playlist) {
    final query = Uri(
      queryParameters: {
        'name': playlist.name,
        if (playlist.coverUrl != null && playlist.coverUrl!.isNotEmpty)
          'cover': playlist.coverUrl!,
      },
    ).query;
    return '/playlist/${playlist.platform.name}/${Uri.encodeComponent(playlist.id)}'
        '${query.isEmpty ? '' : '?$query'}';
  }

  void _openPlaylist(Playlist playlist) {
    if (playlist.id.trim().isEmpty) {
      showErrorSnackBar(context, '该歌单缺少可访问ID，请刷新后重试');
      return;
    }
    context.push(_playlistRoute(playlist));
  }

  Future<void> _deleteMyPlaylist(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定要删除“${playlist.name}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await ref
        .read(myPlaylistsProvider.notifier)
        .deletePlaylist(playlist.id);
    if (!mounted) return;
    showInfoSnackBar(context, ok ? '已删除歌单' : '删除歌单失败');
  }

  /// Opens the export chooser for [playlist], then produces the chosen payload.
  ///
  /// A chooser rather than four menu entries: the formats have different
  /// audiences (a cross-service mover reads `歌名 - 歌手`, Navidrome reads m3u8,
  /// this app reads its own JSON), so they belong on one screen where the user
  /// can see what the options are.
  Future<void> _exportMyPlaylist(Playlist playlist) async {
    final choice = await showModalBottomSheet<PlaylistExportChoice>(
      context: context,
      // The shell's nested navigator would paint this under the floating chrome
      // — same reason as `DownloadButton._showQualityPicker`.
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        // Scrollable on purpose: `showModalBottomSheet` caps an unscrollable
        // sheet at 9/16 of the screen, and this menu — a header plus five
        // options — sits right on that limit on a compact phone. Same reason,
        // and same shape, as `song_actions_sheet.dart`.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  '导出「${playlist.name}」',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
              ),
              const Divider(height: 1),
              for (final option in PlaylistExportChoice.values)
                ListTile(
                  dense: true,
                  leading: Icon(_exportIcon(option)),
                  title: Text(option.label),
                  onTap: () => Navigator.pop(sheetContext, option),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await _runExport(playlist, choice);
  }

  static IconData _exportIcon(PlaylistExportChoice choice) => switch (choice) {
    PlaylistExportChoice.link => Icons.link,
    PlaylistExportChoice.m3u8 => Icons.playlist_play,
    PlaylistExportChoice.text => Icons.text_snippet_outlined,
    PlaylistExportChoice.json => Icons.data_object,
    PlaylistExportChoice.qr => Icons.qr_code_2,
  };

  Future<void> _runExport(
    Playlist playlist,
    PlaylistExportChoice choice,
  ) async {
    final link = await ref
        .read(myPlaylistsProvider.notifier)
        .exportPlaylistLink(playlist.id);
    if (!mounted) return;
    if (link == null || link.isEmpty) {
      showErrorSnackBar(context, '导出失败');
      return;
    }

    if (choice.isRendered) {
      await _showPlaylistQr(playlist, link);
      return;
    }

    // The share-link payload, i.e. `buildPlaylistShareText` through the method
    // that had no caller at all before this.
    if (choice == PlaylistExportChoice.link) {
      await _share(
        (service) => service.sharePlaylist(
          name: playlist.name,
          songCount: playlist.songCount,
          link: link,
        ),
      );
      return;
    }

    final songs = choice.carriesSongs
        ? await ref.read(myPlaylistsProvider.notifier).getSongs(playlist.id)
        : const <Song>[];
    if (!mounted) return;

    final content = PlaylistExport.contentFor(
      choice,
      name: playlist.name,
      songs: songs,
      link: link,
    );
    await _share(
      (service) => service.sharePlaylistExport(
        name: playlist.name,
        content: content,
        formatLabel: choice.label,
      ),
    );
  }

  /// Runs a share, reporting a failure instead of letting it escape: a platform
  /// with no share sheet must say so rather than take the page down.
  Future<void> _share(
    Future<void> Function(ShareService service) run,
  ) async {
    try {
      await run(ref.read(shareServiceProvider));
    } catch (error) {
      if (!mounted) return;
      showErrorSnackBar(context, '分享失败：$error');
    }
  }

  /// Renders the playlist share link as a QR code another phone can scan.
  ///
  /// A QR nobody can read is worse than no QR: the payload is base64url JSON of
  /// every song, and scanning gets unreliable well before the format's own
  /// limit, so a long playlist falls back to pointing at 「分享链接」.
  Future<void> _showPlaylistQr(Playlist playlist, String link) async {
    final payload = qrPayloadForPlaylistLink(link);
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '扫码导入「${playlist.name}」',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                if (payload == null)
                  const Text(
                    '这个歌单太长，链接放不进二维码，请改用「分享链接」',
                    textAlign: TextAlign.center,
                  )
                else
                  QrImageView(
                    data: payload,
                    size: 220,
                    backgroundColor: AppColors.qrBackground,
                    // What the code encodes is what a screen reader should read
                    // out; `QrImageView`'s default label is just "qr code".
                    semanticsLabel: payload,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(platformPlaylistsProvider);
    final myState = ref.watch(myPlaylistsProvider);
    final activeTab = _tabs[_tabController.index];
    final isCreating = activeTab == PlatformType.local
        ? myState.isSaving
        : state.isCreatingFor(activeTab);
    return Scaffold(
      appBar: AppBar(
        title: const Text('歌单'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新当前歌单',
            onPressed: () {
              final platform = _tabs[_tabController.index];
              if (platform == PlatformType.local) {
                ref.read(myPlaylistsProvider.notifier).load();
              } else {
                ref
                    .read(platformPlaylistsProvider.notifier)
                    .loadPlatform(platform);
              }
            },
          ),
          IconButton(
            icon: isCreating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            tooltip: '新建歌单',
            onPressed: isCreating ? null : _createPlaylist,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs
              .map(
                (p) =>
                    Tab(text: p == PlatformType.local ? '我的歌单' : p.displayName),
              )
              .toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((platform) {
          if (platform == PlatformType.local) {
            return _MyPlaylistsTab(
              state: myState,
              onRetry: () => ref.read(myPlaylistsProvider.notifier).load(),
              playlistRoute: _playlistRoute,
              onOpenPlaylist: _openPlaylist,
              onDeletePlaylist: _deleteMyPlaylist,
              onExportPlaylist: _exportMyPlaylist,
            );
          }
          final playlists = state.playlistsFor(platform);
          final error = state.errorsByPlatform[platform];
          final isLoading = state.isLoadingFor(platform);

          if (isLoading && playlists.isEmpty) {
            return const AsyncStateView.loading();
          }
          if (error != null && playlists.isEmpty) {
            return AsyncStateView.error(
              title: '加载歌单失败',
              message: error,
              onRetry: () => ref
                  .read(platformPlaylistsProvider.notifier)
                  .loadPlatform(platform),
            );
          }
          if (playlists.isEmpty) {
            return const AsyncStateView.empty(title: '暂无歌单，或当前平台未登录');
          }
          return Column(
            children: [
              if (isLoading) const LinearProgressIndicator(minHeight: 2),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              Expanded(
                child: AppScrollbar(
                  builder: (controller) => ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      return ListTile(
                        leading: _PlaylistCover(url: playlist.coverUrl),
                        title: Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${playlist.songCount} 首'),
                        trailing: playlist.editable
                            ? const Icon(Icons.edit_note)
                            : const Icon(Icons.bookmark),
                        onTap: () => _openPlaylist(playlist),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _PlaylistCover extends StatelessWidget {
  final String? url;

  const _PlaylistCover({this.url});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 48,
      height: 48,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.queue_music, size: 22),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: url != null && url!.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: url!,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              memCacheWidth: 96,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            )
          : placeholder,
    );
  }
}

class _MyPlaylistsTab extends StatelessWidget {
  final MyPlaylistsState state;
  final VoidCallback onRetry;
  final String Function(Playlist playlist) playlistRoute;
  final void Function(Playlist playlist) onOpenPlaylist;
  final void Function(Playlist playlist) onDeletePlaylist;
  final void Function(Playlist playlist) onExportPlaylist;

  const _MyPlaylistsTab({
    required this.state,
    required this.onRetry,
    required this.playlistRoute,
    required this.onOpenPlaylist,
    required this.onDeletePlaylist,
    required this.onExportPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (state.isLoading && state.playlists.isEmpty) {
      return const AsyncStateView.loading();
    }
    if (state.error != null && state.playlists.isEmpty) {
      return AsyncStateView.error(
        title: '加载歌单失败',
        message: state.error!,
        onRetry: onRetry,
      );
    }
    if (state.playlists.isEmpty) {
      return const AsyncStateView.empty(
        title: '暂无我的歌单，可点击右上角新建或从分享链接导入',
      );
    }
    return Column(
      children: [
        if (state.isLoading || state.isSaving)
          const LinearProgressIndicator(minHeight: 2),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              state.error!,
              style: TextStyle(color: cs.error, fontSize: 13),
            ),
          ),
        Expanded(
          child: AppScrollbar(
            builder: (controller) => ListView.builder(
              controller: controller,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: state.playlists.length,
              itemBuilder: (context, index) {
                final playlist = state.playlists[index];
                return ListTile(
                  leading: const _PlaylistCover(),
                  title: Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${playlist.songCount} 首'),
                  trailing: PopupMenuButton<String>(
                    tooltip: '歌单操作',
                    onSelected: (value) {
                      switch (value) {
                        case 'export':
                          onExportPlaylist(playlist);
                          break;
                        case 'delete':
                          onDeletePlaylist(playlist);
                          break;
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'export',
                        child: ListTile(
                          leading: Icon(Icons.ios_share),
                          title: Text('导出歌单'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('删除歌单'),
                        ),
                      ),
                    ],
                  ),
                  onTap: () => onOpenPlaylist(playlist),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
