import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/app_scrollbar.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AppScrollbar(
        builder: (controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          children: [
            const Text(
              '音乐库',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.favorite, color: Colors.red),
              title: const Text('我喜欢的音乐'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/likes'),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('听歌历史'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/history'),
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('听歌统计'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/listening-stats'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('本地音乐'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/local-music'),
            ),
            ListTile(
              leading: const Icon(Icons.offline_pin_outlined),
              title: const Text('离线缓存'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/offline-cache'),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('智能歌单'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/smart-playlists'),
            ),
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: const Text('歌单'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/platform-playlists'),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: const Text('导入歌单'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/import-playlist'),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('下载管理'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/?tab=3'),
            ),
            // Wave 3 content entries. They live here (and on the discovery tab)
            // instead of a fifth bottom tab: the floating nav capsule has no
            // room for another destination, and both content families are
            // "browse" actions rather than top-level places.
            ListTile(
              leading: const Icon(Icons.leaderboard_outlined),
              title: const Text('榜单中心'),
              subtitle: const Text('各平台榜单 · QQ 热歌榜'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/toplists'),
            ),
            ListTile(
              leading: const Icon(Icons.fiber_new_outlined),
              title: const Text('新歌速递'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/new-songs'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('设置'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings'),
            ),
          ],
        ),
      ),
    );
  }
}
