import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/toplist.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/base/music_platform.dart';
import 'package:mconnect/platform/base/platform_registry.dart';

/// Shared fake used by the Wave 3 content-page tests.
///
/// One configurable [MusicPlatform] instead of a bespoke fake per test file:
/// every content page resolves its platform through [PlatformRegistry], so the
/// tests register this fake for the platform under test and drive its answers
/// (including failures) from the constructor.
class FakeContentPlatform extends MusicPlatform {
  FakeContentPlatform({
    required this.type,
    this.displayName,
    this.toplists = const [],
    this.toplistsError,
    this.rankedSongs = const {},
    this.rankedSongsError,
    this.album,
    this.albumSongs = const [],
    this.albumError,
    this.artist,
    this.artistTopSongs = const [],
    this.artistAlbums = const [],
    this.artistError,
    this.artistTopSongsError,
    this.artistAlbumsError,
    this.newSongs = const [],
    this.newSongsError,
    this.searchPages = const {},
    this.searchError,
    this.playlistResults = const [],
    this.rankingSongs = const [],
    this.rankingError,
    this.supportsArtist = true,
    this.supportsAlbum = true,
    this.supportsNewSongsFlag = true,
    this.loggedIn = false,
  });

  final PlatformType type;
  final String? displayName;
  final List<Toplist> toplists;
  final Object? toplistsError;

  /// `toplistId` → the chart's songs.
  final Map<String, List<RankedSong>> rankedSongs;
  final Object? rankedSongsError;

  final Album? album;
  final List<Song> albumSongs;
  final Object? albumError;

  final Artist? artist;
  final List<Song> artistTopSongs;
  final List<Album> artistAlbums;
  final Object? artistError;
  final Object? artistTopSongsError;
  final Object? artistAlbumsError;

  final List<Song> newSongs;
  final Object? newSongsError;

  /// page number → results.
  final Map<int, List<Song>> searchPages;
  final Object? searchError;
  final List<Playlist> playlistResults;

  final List<Song> rankingSongs;
  final Object? rankingError;

  final bool supportsArtist;
  final bool supportsAlbum;
  final bool supportsNewSongsFlag;
  final bool loggedIn;

  final rankedSongCalls = <({String toplistId, int offset, int num})>[];
  final searchCalls = <({String query, int page, int limit})>[];
  final newSongCalls = <({int limit, NewSongRegion region})>[];
  final albumCalls = <String>[];
  final artistCalls = <String>[];

  @override
  PlatformType get platformType => type;

  @override
  String get platformName => displayName ?? type.displayName;

  @override
  bool get isLoggedIn => loggedIn;

  @override
  bool get supportsArtistPage => supportsArtist;

  @override
  bool get supportsAlbumPage => supportsAlbum;

  @override
  bool get supportsNewSongs => supportsNewSongsFlag;

  @override
  Future<List<Toplist>> getToplists() async {
    final error = toplistsError;
    if (error != null) throw error;
    return toplists;
  }

  @override
  Future<List<RankedSong>> getRankedSongs(
    String toplistId, {
    int offset = 0,
    int num = 100,
    String? period,
  }) async {
    rankedSongCalls.add((toplistId: toplistId, offset: offset, num: num));
    final error = rankedSongsError;
    if (error != null) throw error;
    return rankedSongs[toplistId] ?? const [];
  }

  @override
  Future<Album?> getAlbumDetail(String albumId) async {
    albumCalls.add(albumId);
    final error = albumError;
    if (error != null) throw error;
    return album;
  }

  @override
  Future<List<Song>> getAlbumSongs(String albumId) async {
    final error = albumError;
    if (error != null) throw error;
    return albumSongs;
  }

  @override
  Future<Artist?> getArtistDetail(String artistId) async {
    artistCalls.add(artistId);
    final error = artistError;
    if (error != null) throw error;
    return artist;
  }

  @override
  Future<List<Song>> getArtistTopSongs(
    String artistId, {
    int limit = 50,
  }) async {
    final error = artistTopSongsError;
    if (error != null) throw error;
    return artistTopSongs;
  }

  @override
  Future<List<Album>> getArtistAlbums(
    String artistId, {
    int page = 1,
    int limit = 30,
  }) async {
    final error = artistAlbumsError;
    if (error != null) throw error;
    return artistAlbums;
  }

  @override
  Future<List<Song>> getNewSongs({
    int limit = 100,
    NewSongRegion region = NewSongRegion.all,
  }) async {
    newSongCalls.add((limit: limit, region: region));
    final error = newSongsError;
    if (error != null) throw error;
    return newSongs;
  }

  @override
  Future<List<Song>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    searchCalls.add((query: keyword, page: page, limit: limit));
    final error = searchError;
    if (error != null) throw error;
    return searchPages[page] ?? const [];
  }

  @override
  Future<List<Playlist>> searchPlaylists(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async => playlistResults;

  @override
  Future<List<Song>> getRankingList() async {
    final error = rankingError;
    if (error != null) throw error;
    return rankingSongs;
  }

  @override
  Future<QrLoginResult> getQrCode() async => const QrLoginResult(key: 'k');

  @override
  Stream<QrLoginStatus> pollQrStatus(String key) => const Stream.empty();

  @override
  Future<LoginResult> loginByPhone(String phone, String code) async =>
      const LoginResult(success: false);

  @override
  Future<User?> getUserInfo() async => null;

  @override
  Future<void> logout() async {}

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) async => 'https://example.test/$songId';

  @override
  Future<List<AudioQuality>> getAvailableQualities(String songId) async =>
      const [];

  @override
  Future<String?> getLyrics(String songId) async => null;

  @override
  Future<List<Playlist>> getUserPlaylists() async => const [];

  @override
  Future<List<Song>> getPlaylistDetail(String playlistId) async => const [];

  @override
  Future<List<Song>> getLikedSongs() async => const [];

  @override
  Future<bool> likeSong(String songId, {bool like = true}) async => true;

  @override
  Future<List<Song>> getDailyRecommendations() async => const [];

  @override
  Future<VipLevel> getVipStatus() async => VipLevel.free;

  @override
  Future<Playlist?> parseShareLink(String url) async => null;
}

/// Registers [platform] so the pages can resolve it by type.
FakeContentPlatform registerFake(FakeContentPlatform platform) {
  PlatformRegistry.register(platform);
  return platform;
}

/// Idle [PlayerAudioController] so a real [PlayerNotifier] can run in a widget
/// test without creating a native audio backend (same shape as the `_Idle`
/// fakes in the other player tests).
class IdleAudioController implements PlayerAudioController {
  @override
  bool get playing => false;

  @override
  Duration get position => Duration.zero;

  @override
  double get volume => 1.0;

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  Stream<AudioPlaybackState> get playerStateStream => const Stream.empty();

  @override
  Future<void> stop() async {}

  @override
  Future<void> setUrl(String url) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> bandGains,
  }) async {}

  @override
  Future<void> dispose() async {}
}

/// Catalogue rows from QQ's **real** `GetAll` payload.
///
/// Mirrors what `QqPlatform.getToplists()` does with the same document, so the
/// hub is tested against the field names the live endpoint really uses
/// (`topId`, `title`, `frontPicUrl`, `updateTips`, `totalNum`, `groupName`).
List<Toplist> toplistsFromCatalogueFixture(Map<String, dynamic> payload) {
  final data = (payload['toplist'] as Map)['data'] as Map;
  final toplists = <Toplist>[];
  for (final group in data['group'] as List) {
    final groupName = (group as Map)['groupName']?.toString();
    for (final item in group['toplist'] as List) {
      final row = item as Map;
      toplists.add(
        Toplist(
          id: '${row['topId']}',
          name: (row['title'] ?? '').toString(),
          coverUrl: (row['frontPicUrl'] ?? row['headPicUrl'])?.toString(),
          updateFrequency: row['updateTips']?.toString(),
          songCount: int.tryParse('${row['totalNum']}'),
          period: row['period']?.toString(),
          groupName: groupName,
          intro: row['intro']?.toString(),
        ),
      );
    }
  }
  return toplists;
}

/// Ranked rows from QQ's **real** legacy 热歌榜 payload (`fcg_v8_toplist_cp`).
///
/// The contract under test: the song lives behind a `data` wrapper, `cur_count`
/// is the rank, `old_count - cur_count` is the movement, and `Franking_value` is
/// the raw ranking hint.
List<RankedSong> rankedSongsFromHotCpFixture(Map<String, dynamic> payload) {
  final rows = payload['songlist'] as List;
  final rankedSongs = <RankedSong>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i] as Map;
    final songRow = row['data'] as Map;
    final current = int.tryParse('${row['cur_count']}');
    final previous = int.tryParse('${row['old_count']}');
    final song = Song(
      id: '${songRow['songmid']}',
      platform: PlatformType.qq,
      name: '${songRow['songname']}',
      artists: [
        for (final singer in songRow['singer'] as List)
          Artist(
            id: '${(singer as Map)['mid']}',
            name: '${singer['name']}',
          ),
      ],
      album: songRow['albumname'] == null
          ? null
          : Album(
              id: '${songRow['albummid']}',
              name: '${songRow['albumname']}',
            ),
      duration: Duration(seconds: int.tryParse('${songRow['interval']}') ?? 0),
    );
    rankedSongs.add(
      RankedSong(
        song: song,
        rank: current ?? i + 1,
        rankChange: previous == null || current == null ? null : previous - current,
        isNew: previous == 0,
        rankValue: row['Franking_value']?.toString(),
      ),
    );
  }
  return rankedSongs;
}

Song song(
  String id,
  PlatformType platform, {
  String? name,
  String artist = '歌手',
  String? albumName,
  String? albumId,
  String? artistId,
  int? trackNumber,
  int seconds = 200,
  String? coverUrl,
}) {
  return Song(
    id: id,
    platform: platform,
    name: name ?? '歌曲$id',
    artists: [Artist(id: artistId ?? 'artist', name: artist)],
    album: albumName == null
        ? null
        : Album(
            id: albumId ?? 'album',
            name: albumName,
            coverUrl: coverUrl,
          ),
    albumId: albumId,
    artistId: artistId,
    trackNumber: trackNumber,
    duration: Duration(seconds: seconds),
    coverUrl: coverUrl,
  );
}

RankedSong ranked(
  int rank,
  Song rankedSong, {
  int? change,
  bool? isNew,
  String? rankValue,
}) {
  return RankedSong(
    song: rankedSong,
    rank: rank,
    rankChange: change,
    isNew: isNew,
    rankValue: rankValue,
  );
}
