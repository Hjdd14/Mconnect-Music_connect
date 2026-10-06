import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/network/platform_http.dart';
import '../../../../models/album.dart';
import '../../../../models/artist.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';
import '../../../../platform/base/platform_registry.dart';

/// Identifies one artist: owning platform + its native artist id.
typedef ArtistKey = ({PlatformType platform, String artistId});

/// Artist profile + 热门歌曲 + 专辑列表.
///
/// The three sections load independently: QQ's artist-albums source is the least
/// reliable of them (the legacy endpoint is 404 and the modern module answers
/// `code 500003` on some charts), and losing the album shelf must not blank the
/// whole page. Each section therefore carries its own error, and the UI says
/// which part is missing.
class ArtistPageData {
  final Artist? artist;
  final List<Song> topSongs;
  final List<Album> albums;
  final String? artistError;
  final String? topSongsError;
  final String? albumsError;

  const ArtistPageData({
    this.artist,
    this.topSongs = const [],
    this.albums = const [],
    this.artistError,
    this.topSongsError,
    this.albumsError,
  });

  bool get isEmpty =>
      artist == null && topSongs.isEmpty && albums.isEmpty;
}

final artistPageProvider =
    FutureProvider.autoDispose.family<ArtistPageData, ArtistKey>((
      ref,
      key,
    ) async {
      final platform = PlatformRegistry.get(key.platform);
      if (!platform.supportsArtistPage) {
        throw UnsupportedActionException(platform.platformName);
      }

      Artist? artist;
      String? artistError;
      List<Song> topSongs = const [];
      String? topSongsError;
      List<Album> albums = const [];
      String? albumsError;

      try {
        artist = await platform.getArtistDetail(key.artistId);
      } on Object catch (e) {
        artistError = apiExceptionOf(e).message;
      }
      try {
        topSongs = await platform.getArtistTopSongs(key.artistId, limit: 50);
      } on Object catch (e) {
        topSongsError = apiExceptionOf(e).message;
      }
      try {
        albums = await platform.getArtistAlbums(key.artistId, limit: 30);
      } on Object catch (e) {
        albumsError = apiExceptionOf(e).message;
      }

      return ArtistPageData(
        artist: artist,
        topSongs: topSongs,
        albums: albums,
        artistError: artistError,
        topSongsError: topSongsError,
        albumsError: albumsError,
      );
    });
