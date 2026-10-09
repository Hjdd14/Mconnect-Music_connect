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
import '../../../../platform/base/platform_registry.dart';
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

    final name = await _askPlaylistName();
    if (name == null || name.isEmpty) return;
    final playlist = await ref
        .read(platformPlaylistsProvider.notifier)
        .create(platform, name);
    if (!mounted) return;
    showInfoSnackBar(
      context,
      playlist == null
          ? context.l10n.libraryCreatePlaylistFailed
          : context.l10n.libraryPlaylistCreated,
    );
  }

  Future<void> _createMyPlaylist() async {
    final state = ref.read(myPlaylistsProvider);
    if (state.isSaving) return;

    final name = await _askPlaylistName();
    if (name == null || name.isEmpty) return;

    final playlist = await ref.read(myPlaylistsProvider.notifier).create(name);
    if (!mounted) return;
    showInfoSnackBar(
      context,
      playlist == null
          ? context.l10n.libraryCreatePlaylistFailed
          : context.l10n.libraryPlaylistCreated,
    );
  }

  /// Asks for a playlist name.
  ///
  /// The controller lives in [_PlaylistNameDialog]'s State, not here. The old
  /// shape created it in the caller, awaited `showDialog`, then disposed it
  /// immediately — but the dialog's route is still animating out at that moment,
  /// so the still-mounted `TextField` used a disposed controller. On device that
  /// produced, in order: "A TextEditingController was used after being disposed",
  /// then `'_dependents.isEmpty': is not true`, then "Tried to build dirty widget
  /// in the wrong build scope" — the red screen the user saw. Owning the
  /// controller in the widget ties its lifetime to the widget that uses it.
  Future<String?> _askPlaylistName({
    String? initialValue,
    bool isRename = false,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => _PlaylistNameDialog(
        title: isRename
            ? context.l10n.libraryRenamePlaylist
            : context.l10n.libraryNewPlaylist,
        initialValue: initialValue,
        confirmLabel: isRename
            ? context.l10n.commonConfirm
            : context.l10n.libraryCreate,
      ),
    );
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
      showErrorSnackBar(context, context.l10n.libraryPlaylistMissingId);
      return;
    }
    context.push(_playlistRoute(playlist));
  }

  Future<void> _deleteMyPlaylist(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l = context.l10n;
        return AlertDialog(
          title: Text(l.libraryDeletePlaylist),
          content: Text(l.libraryDeletePlaylistConfirm(playlist.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.commonDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final ok = await ref
        .read(myPlaylistsProvider.notifier)
        .deletePlaylist(playlist.id);
    if (!mounted) return;
    showInfoSnackBar(
      context,
      ok
          ? context.l10n.libraryPlaylistDeleted
          : context.l10n.libraryDeletePlaylistFailed,
    );
  }

  // ── 平台歌单：改名 / 删除 ───────────────────────────────────────────────
  //
  // 走平台适配器的 deletePlaylist / renamePlaylist。这两项在 MusicPlatform 上的
  // 默认实现返回 false（"本平台不支持"），所以**能力不足时 UI 会如实说不支持**，
  // 而不是给一个点了没反应的按钮。

  Future<void> _renamePlatformPlaylist(Playlist playlist) async {
    final name = await _askPlaylistName(
      initialValue: playlist.name,
      isRename: true,
    );
    if (name == null || name.isEmpty || name == playlist.name) return;
    if (!mounted) return;

    final ok = await PlatformRegistry.get(playlist.platform)
        .renamePlaylist(playlist.editableId, name)
        .timeout(const Duration(seconds: 8), onTimeout: () => false);
    if (!mounted) return;
    if (ok) {
      await ref
          .read(platformPlaylistsProvider.notifier)
          .loadPlatform(playlist.platform);
      if (!mounted) return;
      showInfoSnackBar(context, context.l10n.libraryPlaylistRenamed);
    } else {
      showErrorSnackBar(context, context.l10n.libraryPlatformUnsupported);
    }
  }

  Future<void> _deletePlatformPlaylist(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l = context.l10n;
        return AlertDialog(
          title: Text(l.libraryDeletePlaylist),
          content: Text(l.libraryDeletePlaylistConfirm(playlist.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.commonDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final ok = await PlatformRegistry.get(playlist.platform)
        .deletePlaylist(playlist.editableId)
        .timeout(const Duration(seconds: 8), onTimeout: () => false);
    if (!mounted) return;
    if (ok) {
      await ref
          .read(platformPlaylistsProvider.notifier)
          .loadPlatform(playlist.platform);
      if (!mounted) return;
      showInfoSnackBar(context, context.l10n.libraryPlaylistDeleted);
    } else {
      showErrorSnackBar(context, context.l10n.libraryPlatformUnsupported);
    }
  }

  /// Copies a platform playlist into a LOCAL playlist.
  ///
  /// Local rather than "same platform again": a same-platform copy needs that
  /// platform's create + per-song add, and on the platforms whose write endpoints
  /// are not verified that would be a button that silently fails. Importing the
  /// already-fetched song list needs no platform write at all, so it always works.
  Future<void> _copyPlatformPlaylistToLocal(Playlist playlist) async {
    final songs = await ref.read(platformPlaylistsProvider.notifier).loadSongs(
      playlist,
    );
    if (!mounted) return;
    if (songs.isEmpty) {
      showErrorSnackBar(context, context.l10n.libraryPlaylistCopyEmpty);
      return;
    }
    final copy = await ref
        .read(myPlaylistsProvider.notifier)
        .copySongsToLocal(
      name: context.l10n.libraryPlaylistCopyOf(playlist.name),
      songs: songs,
    );
    if (!mounted) return;
    showInfoSnackBar(
      context,
      copy == null
          ? context.l10n.libraryPlaylistCopyFailed
          : context.l10n.libraryPlaylistCopiedLocal(copy.name),
    );
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
                  context.l10n.libraryExportPlaylistNamed(playlist.name),
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
      showErrorSnackBar(context, context.l10n.libraryExportFailed);
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
      showErrorSnackBar(context, context.l10n.libraryShareFailed('$error'));
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
                  context.l10n.libraryScanImportNamed(playlist.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                if (payload == null)
                  Text(
                    context.l10n.libraryQrTooLong,
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
    final l = context.l10n;
    final activeTab = _tabs[_tabController.index];
    final isCreating = activeTab == PlatformType.local
        ? myState.isSaving
        : state.isCreatingFor(activeTab);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.commonPlaylist),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l.libraryRefreshCurrentPlaylist,
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
            tooltip: l.libraryNewPlaylist,
            onPressed: isCreating ? null : _createPlaylist,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabs
              .map(
                (p) => Tab(
                  text: p == PlatformType.local
                      ? l.libraryMyPlaylists
                      : p.displayName,
                ),
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
              title: l.libraryPlaylistLoadFailed,
              message: error,
              onRetry: () => ref
                  .read(platformPlaylistsProvider.notifier)
                  .loadPlatform(platform),
            );
          }
          if (playlists.isEmpty) {
            return AsyncStateView.empty(title: l.libraryPlaylistsEmpty);
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
                        subtitle: Text(context.l10n.librarySongCount(playlist.songCount)),
                        trailing: PopupMenuButton<String>(
                          tooltip: context.l10n.libraryPlaylistActions,
                          onSelected: (value) {
                            switch (value) {
                              case 'rename':
                                _renamePlatformPlaylist(playlist);
                                break;
                              case 'delete':
                                _deletePlatformPlaylist(playlist);
                                break;
                              case 'copyLocal':
                                _copyPlatformPlaylistToLocal(playlist);
                                break;
                            }
                          },
                          itemBuilder: (context) {
                            final l = context.l10n;
                            return [
                              PopupMenuItem(
                                value: 'rename',
                                child: ListTile(
                                  leading: const Icon(Icons.drive_file_rename_outline),
                                  title: Text(l.libraryRenamePlaylist),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'copyLocal',
                                child: ListTile(
                                  leading: const Icon(Icons.copy_all_outlined),
                                  title: Text(l.libraryCopyToLocal),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  leading: const Icon(Icons.delete_outline),
                                  title: Text(l.libraryDeletePlaylist),
                                ),
                              ),
                            ];
                          },
                        ),
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
    final l = context.l10n;
    if (state.isLoading && state.playlists.isEmpty) {
      return const AsyncStateView.loading();
    }
    if (state.error != null && state.playlists.isEmpty) {
      return AsyncStateView.error(
        title: l.libraryPlaylistLoadFailed,
        message: state.error!,
        onRetry: onRetry,
      );
    }
    if (state.playlists.isEmpty) {
      return AsyncStateView.empty(title: l.libraryMyPlaylistsEmpty);
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
                  subtitle: Text(l.librarySongCount(playlist.songCount)),
                  trailing: PopupMenuButton<String>(
                    tooltip: l.libraryPlaylistActions,
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
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'export',
                        child: ListTile(
                          leading: const Icon(Icons.ios_share),
                          title: Text(l.libraryExportPlaylist),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: const Icon(Icons.delete_outline),
                          title: Text(l.libraryDeletePlaylist),
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

/// A single-field name dialog that owns its [TextEditingController].
///
/// This exists because the obvious shape — create the controller in the caller,
/// `await showDialog`, then `dispose()` — is wrong: when `showDialog`'s future
/// completes, the dialog's route is still animating out and its `TextField` is
/// still mounted, so it reads a controller that has already been disposed. On
/// device that surfaced as a red screen with
/// `'_dependents.isEmpty': is not true` followed by "Tried to build dirty widget
/// in the wrong build scope".
///
/// Binding the controller to a `State` makes its lifetime exactly the widget's:
/// `initState` creates it, `dispose` releases it, and no caller has to reason
/// about route animation timing. `settings_page.dart`'s `_BackgroundEditorDialogState`
/// is the same pattern already used elsewhere in this repository.
class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({
    required this.title,
    required this.confirmLabel,
    this.initialValue,
  });

  final String title;
  final String confirmLabel;
  final String? initialValue;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l.libraryPlaylistName),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
