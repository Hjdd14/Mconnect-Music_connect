import 'package:flutter/material.dart';

import '../../../toplist/presentation/pages/toplists_page.dart';

/// `/rankings` — the legacy "排行榜" entry.
///
/// It used to be a flat "hot songs per platform" tab list that silently dropped
/// any platform whose call failed, which is how QQ disappeared from it. 榜单中心
/// ([/toplists]) supersedes it: it lists every chart each platform publishes
/// (QQ's 30 charts including the pinned 300-track 热歌榜), so this route now
/// renders the same hub, and deep links / back-stack entries into `/rankings`
/// land on real content instead of the old flat list.
class RankingsPage extends StatelessWidget {
  const RankingsPage({super.key});

  @override
  Widget build(BuildContext context) => const ToplistsPage();
}
