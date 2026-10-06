import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/platform_type.dart';
import '../../../../models/toplist.dart';
import '../../../../platform/base/platform_registry.dart';

/// Identifies one chart: platform + its native id (QQ `topId` as a string).
typedef ToplistKey = ({PlatformType platform, String toplistId});

/// How many tracks one chart page asks for.
///
/// QQ's 热歌榜 has **300** tracks and its own adapter pages the legacy endpoint
/// internally (50 per request), so the whole chart arrives from one call here.
const int toplistSongLimit = 300;

/// Chart contents, with rank and movement.
///
/// `RankedSong.rankChange` is positive when a song moved **up** — QQ reports it
/// as `old_count - cur_count` and the adapter already normalises it.
final toplistSongsProvider =
    FutureProvider.autoDispose.family<List<RankedSong>, ToplistKey>((
      ref,
      key,
    ) async {
      final platform = PlatformRegistry.get(key.platform);
      return platform
          .getRankedSongs(key.toplistId, num: toplistSongLimit)
          .timeout(const Duration(seconds: 30));
    });
