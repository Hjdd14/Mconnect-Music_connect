import 'dart:async';
// Flutter 3.47.5 在 material.dart 中新增了 `RepeatMode`
// (src/widgets/repeating_animation_builder.dart)，与本项目的
// `RepeatMode` 枚举（player_provider.dart）命名冲突。此处隐藏 Flutter 的
// 版本，使 `RepeatMode` 唯一解析到本项目定义。
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/diagnostics/diagnostics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../models/song.dart';
import '../../../download/presentation/widgets/download_button.dart';
import '../../../library/presentation/providers/likes_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/lyrics_display.dart';
import '../widgets/playback_options_sheet.dart';
import '../widgets/playlist_picker_sheet.dart';
import '../widgets/quality_bottom_sheet.dart';
import '../../../../core/utils/snackbar_helper.dart';
import '../../../../l10n/l10n.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _showLyrics = false;
  bool _isSeeking = false;
  double _dismissDragDistance = 0;
  Timer? _positionTimer;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  void _syncProgressFromProvider({bool notify = false}) {
    if (_isSeeking) return;
    final playerState = ref.read(playerProvider);
    final newPos = playerState.position;
    final newDur = playerState.duration;
    if (newPos == _position && newDur == _duration) return;

    if (notify) {
      if (!mounted) return;
      setState(() {
        _position = newPos;
        _duration = newDur;
      });
      return;
    }

    _position = newPos;
    _duration = newDur;
  }

  @override
  void initState() {
    super.initState();
    _syncProgressFromProvider();
    _positionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _syncProgressFromProvider(notify: true);
    });
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _returnToSource() {
    final from = GoRouterState.of(context).uri.queryParameters['from'];
    final hasValidSource =
        from != null &&
        from.isNotEmpty &&
        Uri.tryParse(from)?.path != '/player';
    DiagnosticsService.instance.record(
      'navigation',
      'close_player',
      data: {
        'from': from,
        'can_pop': context.canPop(),
        'has_valid_source': hasValidSource,
      },
    );
    if (context.canPop()) {
      context.pop();
    } else if (hasValidSource) {
      context.go(from);
    } else {
      context.go('/');
    }
  }

  void _handleDismissDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    if (delta > 0) {
      _dismissDragDistance += delta;
    }
  }

  void _handleDismissDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldDismiss = _dismissDragDistance > 96 || velocity > 700;
    _dismissDragDistance = 0;
    if (shouldDismiss) {
      _returnToSource();
    }
  }

  void _toggleLyrics() {
    setState(() => _showLyrics = !_showLyrics);
  }

  /// Vertical space the column needs for everything that is **not** the lyrics
  /// panel: the spacers, title, artist, quality chip, slider, time labels and the
  /// transport row.
  ///
  /// A constant rather than a measurement because it must be known before the
  /// column is laid out. It only has to be an upper bound: over-reserving shrinks
  /// the lyrics panel a little, under-reserving clips the transport row — which is
  /// the bug this guards.
  static const double _nonLyricsColumnHeight = 470;

  /// Height for the lyrics panel so the whole column fits [availableHeight].
  ///
  /// `artworkSize` is the floor rather than a fixed number, because the panel must
  /// stay taller than the artwork it replaces — that relationship is a product
  /// contract an existing test asserts, and a fixed floor can undercut it on a
  /// short viewport (the default test surface is 600 dp tall).
  ///
  /// The panel's content is a `ListView`, so shrinking it is safe.
  static double _lyricsPanelHeight(double availableHeight, double artworkSize) {
    final remaining = availableHeight - _nonLyricsColumnHeight;
    final floor = artworkSize + 8;
    if (remaining < floor) return floor;
    if (remaining > 400) return 400;
    return remaining;
  }

  @override
  Widget build(BuildContext context) {
    // Only watch stable fields; position/duration read via Timer
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final currentQuality = ref.watch(
      playerProvider.select((s) => s.currentQuality),
    );
    final isShuffle = ref.watch(playerProvider.select((s) => s.isShuffle));
    final repeatMode = ref.watch(playerProvider.select((s) => s.repeatMode));
    final isTransitioning = ref.watch(
      playerProvider.select((s) => s.isTransitioning),
    );
    final likedSongs = ref.watch(likesProvider.select((s) => s.songs));
    final notifier = ref.read(playerProvider.notifier);
    final position = _position;
    final duration = _duration;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: _handleDismissDragUpdate,
      onVerticalDragEnd: _handleDismissDragEnd,
      onVerticalDragCancel: () => _dismissDragDistance = 0,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: context.l10n.playerCollapse,
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: _returnToSource,
          ),
          title: Text(context.l10n.playerNowPlaying),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: _showLyrics
                  ? context.l10n.playerToggleArtwork
                  : context.l10n.playerToggleLyrics,
              icon: Icon(
                _showLyrics ? Icons.album : Icons.lyrics_outlined,
                size: 22,
              ),
              onPressed: song == null ? null : _toggleLyrics,
            ),
            if (song != null)
              IconButton(
                tooltip: context.l10n.playerLike,
                icon: Icon(
                  likedSongs.any(
                        (s) => s.id == song.id && s.platform == song.platform,
                      )
                      ? Icons.favorite
                      : Icons.favorite_border,
                ),
                color:
                    likedSongs.any(
                      (s) => s.id == song.id && s.platform == song.platform,
                    )
                    ? Colors.red
                    : null,
                onPressed: () async {
                  final result = await ref
                      .read(likesProvider.notifier)
                      .toggleLike(song);
                  if (!context.mounted) return;
                  showInfoSnackBar(
                      context,
                      result
                          ? context.l10n.playerAddedToLikes
                          : context.l10n.playerRemovedFromLikes,
                    );
                },
              ),
            if (song != null) DownloadButton(song: song),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (song == null) return;
                switch (value) {
                  case 'add_to_queue':
                    ref.read(playerProvider.notifier).addToQueue(song);
                    showSuccessSnackBar(context, context.l10n.playerAddedToQueue);
                    break;
                  case 'copy_name':
                    final text = '${song.artistNames} - ${song.name}';
                    Clipboard.setData(ClipboardData(text: text));
                    showSuccessSnackBar(context, context.l10n.playerSongInfoCopied);
                    break;
                  case 'add_to_playlist':
                    _showPlaylistPicker(context, song);
                    break;
                  case 'playback_options':
                    PlaybackOptionsSheet.show(context);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'playback_options',
                  child: ListTile(
                    leading: const Icon(Icons.tune),
                    title: Text(context.l10n.playerPlaybackSettings),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'add_to_playlist',
                  child: ListTile(
                    leading: const Icon(Icons.playlist_add),
                    title: Text(context.l10n.playerAddToPlatformPlaylist),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'add_to_queue',
                  child: ListTile(
                    leading: const Icon(Icons.queue_music),
                    title: Text(context.l10n.playerAddToQueue),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'copy_name',
                  child: ListTile(
                    leading: const Icon(Icons.copy),
                    title: Text(context.l10n.playerCopySongInfo),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
        body: song == null
            ? Center(child: Text(context.l10n.playerNotPlaying))
            : LayoutBuilder(
                builder: (context, constraints) {
                  final artworkSize = constraints.maxHeight < 620
                      ? 220.0
                      : 280.0;
                  // The lyrics panel gets whatever is left after the rest of the
                  // column, capped so it never grows unbounded on a tall screen and
                  // floored so it stays usable on a short one.
                  //
                  // This used to be a flat 400 dp (or 58 % of the height, whichever
                  // was smaller). On the reporter's ~736 dp-tall device that pushed
                  // the whole column past the viewport by ~21 dp, and because the
                  // `SingleChildScrollView` starts at offset 0 the shortfall was cut
                  // off at the *bottom* — the shuffle/previous/play/next/repeat row
                  // sank below the screen when lyrics were opened.
                  //
                  // The panel's content is a `ListView`, so shrinking it is safe.
                  final lyricsHeight = _lyricsPanelHeight(
                    constraints.maxHeight,
                    artworkSize,
                  );
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 16),
                            // Album art or Lyrics with crossfade
                            GestureDetector(
                              key: const ValueKey('player_middle_toggle'),
                              behavior: HitTestBehavior.opaque,
                              onTap: _toggleLyrics,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: _showLyrics
                                    ? Container(
                                        key: const ValueKey(
                                          'player_lyrics_panel',
                                        ),
                                        height: lyricsHeight,
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withValues(alpha: 0.42),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: const LyricsDisplay(),
                                      )
                                    : SizedBox(
                                        key: const ValueKey(
                                          'player_artwork_panel',
                                        ),
                                        width: artworkSize,
                                        height: artworkSize,
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: song.coverUrl != null
                                              ? CachedNetworkImage(
                                                  imageUrl: song.coverUrl!,
                                                  width: artworkSize,
                                                  height: artworkSize,
                                                  memCacheWidth:
                                                      (artworkSize * 2).round(),
                                                  fit: BoxFit.cover,
                                                  placeholder: (_, _) =>
                                                      Container(
                                                        width: artworkSize,
                                                        height: artworkSize,
                                                        color:
                                                            AppColors
                                                                .placeholder(
                                                                  context,
                                                                ),
                                                        child: const Icon(
                                                          Icons.music_note,
                                                          size: 80,
                                                        ),
                                                      ),
                                                  errorWidget: (_, _, _) =>
                                                      Container(
                                                        width: artworkSize,
                                                        height: artworkSize,
                                                        color:
                                                            AppColors
                                                                .placeholder(
                                                                  context,
                                                                ),
                                                        child: const Icon(
                                                          Icons.music_note,
                                                          size: 80,
                                                        ),
                                                      ),
                                                )
                                              : Container(
                                                  width: artworkSize,
                                                  height: artworkSize,
                                                  color: AppColors.placeholder(
                                                    context,
                                                  ),
                                                  child: Icon(
                                                    Icons.music_note,
                                                    size: 80,
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.outline,
                                                  ),
                                                ),
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            // Song name with fade transition
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: Text(
                                song.name,
                                key: ValueKey(song.id),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 8),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: Text(
                                song.artistNames,
                                key: ValueKey('${song.id}_artist'),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Quality badge
                            GestureDetector(
                              onTap: () => showQualitySheet(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.equalizer,
                                      size: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      currentQuality.displayNameFor(
                                        song.platform,
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      Icons.keyboard_arrow_down,
                                      size: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Progress bar
                            Slider(
                              value: duration.inMilliseconds > 0
                                  ? position.inMilliseconds.toDouble().clamp(
                                      0,
                                      duration.inMilliseconds.toDouble(),
                                    )
                                  : 0,
                              max: duration.inMilliseconds > 0
                                  ? duration.inMilliseconds.toDouble()
                                  : 1,
                              onChangeStart: (_) {
                                setState(() => _isSeeking = true);
                              },
                              onChanged: (v) {
                                setState(() {
                                  _position = Duration(milliseconds: v.toInt());
                                });
                              },
                              onChangeEnd: (v) {
                                final target = Duration(
                                  milliseconds: v.toInt(),
                                );
                                setState(() {
                                  _isSeeking = false;
                                  _position = target;
                                });
                                unawaited(notifier.seek(target));
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(position),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  Text(
                                    _formatDuration(duration),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Controls
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                  // Icon-only controls carry a `tooltip`: it is
                                  // the screen reader's label as well as the
                                  // desktop hover hint, and the transport row
                                  // previously exposed none of them.
                                  tooltip: context.l10n.playerShuffle,
                                  icon: Icon(
                                    Icons.shuffle,
                                    size: 22,
                                    color: isShuffle
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.outline,
                                  ),
                                  onPressed: notifier.toggleShuffle,
                                ),
                                IconButton(
                                  tooltip: context.l10n.playerPrevious,
                                  icon: const Icon(
                                    Icons.skip_previous,
                                    size: 32,
                                  ),
                                  onPressed: notifier.skipToPrevious,
                                ),
                                AnimatedScale(
                                  scale: isPlaying ? 1.0 : 0.9,
                                  duration: const Duration(milliseconds: 200),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    child: isTransitioning
                                        ? const SizedBox(
                                            width: 52,
                                            height: 52,
                                            child: Padding(
                                              padding: EdgeInsets.all(14),
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: AppColors.onBrand,
                                              ),
                                            ),
                                          )
                                        : IconButton(
                                            tooltip: isPlaying
                                                ? context.l10n.playerPause
                                                : context.l10n.playerPlay,
                                            icon: Icon(
                                              isPlaying
                                                  ? Icons.pause
                                                  : Icons.play_arrow,
                                              size: 36,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onPrimary,
                                            ),
                                            onPressed: notifier.togglePlay,
                                          ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: context.l10n.playerNext,
                                  icon: const Icon(Icons.skip_next, size: 32),
                                  onPressed: notifier.skipToNext,
                                ),
                                IconButton(
                                  tooltip: context.l10n.playerRepeat,
                                  icon: Icon(
                                    repeatMode == RepeatMode.one
                                        ? Icons.repeat_one
                                        : Icons.repeat,
                                    size: 24,
                                    color: repeatMode == RepeatMode.off
                                        ? Theme.of(context).colorScheme.outline
                                        : Theme.of(context).colorScheme.primary,
                                  ),
                                  onPressed: notifier.cycleRepeatMode,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _showPlaylistPicker(BuildContext context, Song song) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => PlaylistPickerSheet(song: song),
    );
    if (!context.mounted) return;
    if (ok == true) {
      showSuccessSnackBar(context, context.l10n.playerAddedToPlaylist);
    } else if (ok == false) {
      showErrorSnackBar(context, context.l10n.playerAddToPlaylistFailed);
    }
  }
}
