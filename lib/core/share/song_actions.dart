import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/download/presentation/providers/download_provider.dart';
import '../../features/library/presentation/providers/likes_provider.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../../features/player/presentation/widgets/playlist_picker_sheet.dart';
import '../../models/audio_quality.dart';
import '../../models/song.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/song_actions_sheet.dart';
import 'share_links.dart';
import 'share_service.dart';

/// What a menu action produced, ready to be shown to the user.
///
/// A null [message] means "no feedback needed" (the system share sheet is its
/// own feedback).
class SongActionResult {
  const SongActionResult({this.message, this.success = true});

  final String? message;
  final bool success;
}

/// The effects [performSongAction] needs, so the dispatch logic — which is
/// where the bugs live — can be unit-tested without a widget tree, a player or
/// a network.
class SongActionDeps {
  const SongActionDeps({
    required this.playNext,
    required this.pickPlaylist,
    required this.download,
    required this.toggleLike,
    required this.copyText,
    required this.shareText,
  });

  /// Queues [song] to play right after the current one; returns the message.
  final Future<String> Function(Song song) playNext;

  /// Lets the user choose a playlist and adds [song]; true when it was added.
  final Future<bool> Function(Song song) pickPlaylist;

  /// Enqueues a download and returns the quality it was queued at.
  final Future<AudioLevel> Function(Song song) download;

  /// Toggles the like state; returns the new state.
  final Future<bool> Function(Song song) toggleLike;

  final Future<void> Function(String text) copyText;

  final Future<void> Function(Song song) shareText;
}

/// Wires the deps to the live providers.
///
/// [context] (optional) is only needed by the "添加到歌单" action, which opens
/// the playlist picker sheet.
SongActionDeps liveSongActionDeps(WidgetRef ref, {BuildContext? context}) {
  return SongActionDeps(
    playNext: (song) async {
      final player = ref.read(playerProvider.notifier);
      if (ref.read(playerProvider).currentSong == null) {
        // Nothing is playing, so "next" would be a queue nobody hears: start it.
        await player.playSong(song);
        return '开始播放：${song.name}';
      }
      // Pure queue rewrite — the current track keeps playing.
      player.playNext(song);
      return '下一首播放：${song.name}';
    },
    pickPlaylist: (song) async {
      if (context == null || !context.mounted) return false;
      final added = await showModalBottomSheet<bool>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (_) => PlaylistPickerSheet(song: song),
      );
      return added ?? false;
    },
    download: (song) async {
      final notifier = ref.read(downloadProvider.notifier);
      // Pick the best quality the account is entitled to instead of silently
      // downloading 128k: the menu has no room for the quality picker the
      // download button shows.
      var level = AudioLevel.low;
      if (await notifier.checkVipForDownload(song, AudioLevel.lossless)) {
        level = AudioLevel.lossless;
      } else if (await notifier.checkVipForDownload(song, AudioLevel.medium)) {
        level = AudioLevel.medium;
      }
      await notifier.startDownload(song, level);
      return level;
    },
    toggleLike: (song) => ref.read(likesProvider.notifier).toggleLike(song),
    copyText: (text) => Clipboard.setData(ClipboardData(text: text)),
    shareText: (song) => ref.read(shareServiceProvider).shareSong(song),
  );
}

/// Runs one choice from the song menu.
///
/// Never throws: a platform failure becomes a failed [SongActionResult] so the
/// menu can report it instead of leaking an exception into the UI.
Future<SongActionResult> performSongAction({
  required SongAction action,
  required Song song,
  required SongActionDeps deps,
  bool isLiked = false,
}) async {
  try {
    switch (action) {
      case SongAction.playNext:
        return SongActionResult(message: await deps.playNext(song));
      case SongAction.addToPlaylist:
        final added = await deps.pickPlaylist(song);
        return added
            ? const SongActionResult(message: '已添加到歌单')
            : const SongActionResult(message: '未添加到歌单', success: false);
      case SongAction.download:
        final level = await deps.download(song);
        return SongActionResult(
          message: '已开始下载：${song.name}（${level.displayNameFor(song.platform)}）',
        );
      case SongAction.toggleLike:
        final liked = await deps.toggleLike(song);
        return SongActionResult(message: liked ? '已添加到我喜欢' : '已取消喜欢');
      case SongAction.copyLink:
        await deps.copyText(ShareLinks.songLink(song));
        return const SongActionResult(message: '已复制歌曲链接');
      case SongAction.share:
        await deps.shareText(song);
        return const SongActionResult();
    }
  } catch (e) {
    return SongActionResult(message: '操作失败：$e', success: false);
  }
}

/// Shows the frozen [showSongActionsSheet] and performs whatever was chosen,
/// reporting the result through the shared snackbar helpers.
///
/// This is the entry point long-press callers should use — it keeps the
/// "what does each action do" logic in one place instead of duplicating a
/// switch in every song list.
Future<SongActionResult?> showSongActionsMenu(
  BuildContext context,
  WidgetRef ref, {
  required Song song,
  bool isLiked = false,
  bool isDownloaded = false,
  bool isLocal = false,
}) async {
  final action = await showSongActionsSheet(
    context,
    song: song,
    isLiked: isLiked,
    isDownloaded: isDownloaded,
    isLocal: isLocal,
  );
  if (action == null || !context.mounted) return null;

  final result = await performSongAction(
    action: action,
    song: song,
    deps: liveSongActionDeps(ref, context: context),
    isLiked: isLiked,
  );

  if (!context.mounted) return result;
  final message = result.message;
  if (message != null) {
    if (result.success) {
      showSuccessSnackBar(context, message);
    } else {
      showErrorSnackBar(context, message);
    }
  }
  return result;
}
