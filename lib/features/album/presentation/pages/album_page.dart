import 'package:flutter/material.dart';

import '../../../../models/platform_type.dart';

/// Album detail: cover, release info and the track list.
class AlbumPage extends StatelessWidget {
  const AlbumPage({
    super.key,
    required this.platform,
    required this.albumId,
    this.albumName,
  });

  final PlatformType platform;
  final String albumId;
  final String? albumName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(albumName ?? '专辑')),
      body: Center(
        child: Text('${platform.displayName} 专辑 $albumId 建设中'),
      ),
    );
  }
}
