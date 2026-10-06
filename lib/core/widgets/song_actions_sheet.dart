import 'package:flutter/material.dart';

import '../../models/song.dart';

/// Actions a song can offer from its long-press (or overflow) menu.
enum SongAction {
  playNext,
  addToPlaylist,
  download,
  toggleLike,
  copyLink,
  share,
}

/// Shared song action sheet.
///
/// The API is frozen here in Wave 0 so the content pages and the interaction
/// workstream can both call it without waiting for each other. This file owns
/// *presenting* the choices; the interaction workstream owns what each choice
/// does (and its tests), so a caller gets a [SongAction] back and dispatches it.
///
/// Note `useRootNavigator: true`: the shell hosts go_router's nested navigator,
/// and a sheet pushed onto that nested navigator is painted under the bottom
/// navigation capsules (this was fixed once already for modal sheets — see the
/// v1.3.2 notes in `docs/mconnect-improvement-plan.md`).
Future<SongAction?> showSongActionsSheet(
  BuildContext context, {
  required Song song,
  bool isLiked = false,
  bool isDownloaded = false,
  bool isLocal = false,
}) {
  return showModalBottomSheet<SongAction>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        // Scrollable on purpose: `showModalBottomSheet` caps an unscrollable
        // sheet at 9/16 of the screen, and this menu's six rows plus the header
        // and drag handle exceed that on a 360x800 phone (measured: 417px of
        // content in a 402px limit), which pushed the last action out of reach.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  song.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                subtitle: Text(
                  song.artistNames,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              _ActionTile(
                icon: Icons.playlist_play,
                label: '下一首播放',
                action: SongAction.playNext,
              ),
              if (!isLocal)
                _ActionTile(
                  icon: Icons.playlist_add,
                  label: '添加到歌单',
                  action: SongAction.addToPlaylist,
                ),
              if (!isLocal)
                _ActionTile(
                  icon: isDownloaded
                      ? Icons.download_done
                      : Icons.download_outlined,
                  label: isDownloaded ? '已下载' : '下载',
                  action: SongAction.download,
                  enabled: !isDownloaded,
                ),
              if (!isLocal)
                _ActionTile(
                  icon: isLiked ? Icons.favorite : Icons.favorite_border,
                  label: isLiked ? '取消喜欢' : '喜欢',
                  action: SongAction.toggleLike,
                ),
              _ActionTile(
                icon: Icons.link,
                label: '复制链接',
                action: SongAction.copyLink,
              ),
              if (!isLocal)
                _ActionTile(
                  icon: Icons.share_outlined,
                  label: '分享',
                  action: SongAction.share,
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.action,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final SongAction action;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      enabled: enabled,
      onTap: enabled
          ? () => Navigator.of(context, rootNavigator: true).pop(action)
          : null,
    );
  }
}
