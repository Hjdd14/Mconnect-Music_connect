import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
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
      // Every song list in the app shows this menu, so its labels live in the
      // shared `common*` group (docs/i18n-migration-plan.md §1.2 rule 3) — later
      // batches only reference them instead of writing the same strings again.
      final l = sheetContext.l10n;
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
                label: l.commonPlayNext,
                action: SongAction.playNext,
              ),
              if (!isLocal)
                _ActionTile(
                  icon: Icons.playlist_add,
                  label: l.commonAddToPlaylist,
                  action: SongAction.addToPlaylist,
                ),
              if (!isLocal)
                _ActionTile(
                  icon: isDownloaded
                      ? Icons.download_done
                      : Icons.download_outlined,
                  label: isDownloaded ? l.commonDownloaded : l.commonDownload,
                  action: SongAction.download,
                  enabled: !isDownloaded,
                ),
              if (!isLocal)
                _ActionTile(
                  icon: isLiked ? Icons.favorite : Icons.favorite_border,
                  label: isLiked ? l.commonUnlike : l.commonLike,
                  action: SongAction.toggleLike,
                ),
              _ActionTile(
                icon: Icons.link,
                label: l.commonCopyLink,
                action: SongAction.copyLink,
              ),
              if (!isLocal)
                _ActionTile(
                  icon: Icons.share_outlined,
                  // Reuses the existing `share` key (zh/en already translated).
                  label: l.share,
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
