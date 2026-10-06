import 'package:flutter/material.dart';

import '../../../../models/platform_type.dart';

/// 榜单中心 — every chart the platforms publish, grouped by platform/group.
///
/// Wave 0 placeholder: the route and its arguments are frozen so the discovery
/// entry points can be wired, and the content workstream replaces this body.
class ToplistsPage extends StatelessWidget {
  const ToplistsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('榜单中心')),
      body: const Center(child: Text('榜单中心建设中')),
    );
  }
}

/// One chart's songs, with rank and movement.
///
/// QQ's 热歌榜 is reachable both here (`platform: qq, toplistId: '26'`) and
/// through its own highlighted entry on [ToplistsPage].
class ToplistDetailPage extends StatelessWidget {
  const ToplistDetailPage({
    super.key,
    required this.platform,
    required this.toplistId,
    this.toplistName,
  });

  final PlatformType platform;
  final String toplistId;
  final String? toplistName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(toplistName ?? '榜单')),
      body: Center(
        child: Text('${platform.displayName} 榜单 $toplistId 建设中'),
      ),
    );
  }
}
