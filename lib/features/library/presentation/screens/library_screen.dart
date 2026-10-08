import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/app_scrollbar.dart';
import '../../../../l10n/l10n.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SafeArea(
      child: AppScrollbar(
        builder: (controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          children: [
            Text(
              l.navLibrary,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.favorite, color: Colors.red),
              title: Text(l.libraryLikes),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/likes'),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(l.libraryHistory),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/history'),
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: Text(l.statsTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/listening-stats'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              // 平台层与这行说的是同一件事（"本地"），复用现成的 platformLocal，
              // 不再新造一个同义 key（地图 §1.2 规则 4）。
              title: Text(l.platformLocal),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/local-music'),
            ),
            ListTile(
              leading: const Icon(Icons.offline_pin_outlined),
              title: Text(l.cacheTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/offline-cache'),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: Text(l.smartPlaylistTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/smart-playlists'),
            ),
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(l.commonPlaylist),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/platform-playlists'),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: Text(l.libraryImportPlaylist),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/import-playlist'),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: Text(l.downloadTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/?tab=3'),
            ),
            // 榜单中心 / 新歌速递 deliberately live on the 发现 tab only.
            //
            // They used to be duplicated here as well, which made this list long
            // enough to push 设置 below the fold on a compact screen for no
            // benefit — the same two destinations were one tab away. See
            // test/library_discovery_entries_test.dart: it fails if either the
            // library copy comes back *or* the discovery entry disappears, so
            // the content cannot quietly become unreachable.
            //
            // They are on a tab rather than a fifth bottom destination because
            // the floating nav capsule has no room for another one, and both
            // content families are "browse" actions rather than top-level places.
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: Text(l.settingsTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings'),
            ),
          ],
        ),
      ),
    );
  }
}
