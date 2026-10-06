import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../models/album.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';
import '../../../../platform/base/platform_registry.dart';

/// Identifies one album: owning platform + its native album id.
typedef AlbumKey = ({PlatformType platform, String albumId});

/// Album metadata plus its tracks, loaded together.
///
/// Loading both in one provider means the page can render "封面 + 曲目" from a
/// single async state, and a platform that cannot serve album pages fails once
/// with a typed [UnsupportedActionException] instead of showing a half-empty
/// page.
class AlbumDetailData {
  final Album? album;
  final List<Song> songs;

  const AlbumDetailData({this.album, this.songs = const []});

  bool get isEmpty => album == null && songs.isEmpty;
}

/// Album tracks in track order.
///
/// Platforms that number their tracks (网易云 `no`, QQ `index_album`, local
/// files' tags) get sorted; when any track lacks a number the platform's own
/// order is kept, because a half-sorted list is worse than the original one.
List<Song> sortAlbumSongs(List<Song> songs) {
  if (songs.length < 2) return songs;
  if (songs.any((song) => song.trackNumber == null)) return songs;
  final numbered = List<Song>.from(songs);
  numbered.sort((a, b) => a.trackNumber!.compareTo(b.trackNumber!));
  return numbered;
}

final albumDetailProvider =
    FutureProvider.autoDispose.family<AlbumDetailData, AlbumKey>((ref, key) async {
      final platform = PlatformRegistry.get(key.platform);
      if (!platform.supportsAlbumPage) {
        throw UnsupportedActionException(platform.platformName);
      }
      final album = await platform.getAlbumDetail(key.albumId);
      final songs = await platform.getAlbumSongs(key.albumId);
      return AlbumDetailData(album: album, songs: sortAlbumSongs(songs));
    });
