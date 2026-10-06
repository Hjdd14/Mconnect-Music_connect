import 'package:flutter/material.dart';

import '../../../../models/platform_type.dart';

/// Artist detail: profile, top songs and albums.
class ArtistPage extends StatelessWidget {
  const ArtistPage({
    super.key,
    required this.platform,
    required this.artistId,
    this.artistName,
  });

  final PlatformType platform;
  final String artistId;
  final String? artistName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(artistName ?? '歌手')),
      body: Center(
        child: Text('${platform.displayName} 歌手 $artistId 建设中'),
      ),
    );
  }
}
