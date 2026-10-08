import '../../lyrics/models/lyrics_bundle.dart';
import '../../models/song.dart';
import '../../models/user.dart';
import '../../models/playlist.dart';
import '../../models/album.dart';
import '../../models/artist.dart';
import '../../models/audio_quality.dart';
import '../../models/toplist.dart';
import '../../models/recommendation_source.dart';
import '../base/platform_enum.dart';
import '../../core/storage/session_storage.dart';

enum LoginMethod { qrCode, phone }

enum QrLoginStatus { waiting, scanned, success, expired, failed }

/// Region filter for the "new songs" (新歌速递) pages.
///
/// Each platform numbers these differently (QQ `type=1内地/2欧美/3日本/4韩国/6港台`,
/// 网易云 `type=7华语/96欧美/8日本/16韩国`), so the platforms map this enum onto
/// their own ids instead of the UI passing raw numbers around.
enum NewSongRegion { all, chinese, western, japanese, korean, hongKongTaiwan }

class QrLoginResult {
  final String key;
  final String? qrUrl;
  final List<int>? qrBytes;

  const QrLoginResult({required this.key, this.qrUrl, this.qrBytes});
}

class LoginResult {
  final bool success;
  final User? user;
  final String? cookie;
  final String? error;

  const LoginResult({required this.success, this.user, this.cookie, this.error});
}

abstract class MusicPlatform {
  PlatformType get platformType;
  String get platformName;

  // Auth
  Future<QrLoginResult> getQrCode();
  Stream<QrLoginStatus> pollQrStatus(String key);
  Future<LoginResult> sendPhoneCode(String phone) async {
    return const LoginResult(success: false, error: '当前平台暂不支持获取验证码');
  }
  Future<LoginResult> loginByPhone(String phone, String code);
  Future<User?> getUserInfo();
  bool get isLoggedIn;
  Future<void> logout();

  // Session persistence
  Future<void> saveSession(SessionStorage storage) => Future.value();
  Future<void> restoreSession(SessionStorage storage) => Future.value();

  // Search
  Future<List<Song>> search(String keyword, {int page = 1, int limit = 30});
  Future<List<Playlist>> searchPlaylists(String keyword, {int page = 1, int limit = 30}) async {
    return const [];
  }

  // Playback
  Future<String> getSongUrl(String songId, {AudioLevel quality = AudioLevel.low});
  Future<List<AudioQuality>> getAvailableQualities(String songId);

  // Lyrics
  Future<String?> getLyrics(String songId);

  /// Every lyric track this platform has for [songId], **kept per format**.
  ///
  /// `yrc` (word-by-word) is a different format from `lrc`, not a richer LRC,
  /// so the tracks cannot be pre-concatenated. The default implementation wraps
  /// [getLyrics] into one LRC track, which is what every platform that has a
  /// single payload needs — a platform with several tracks overrides this.
  ///
  /// Returns null when the platform has no lyrics for the song.
  Future<LyricsBundle?> getLyricsBundle(String songId) async {
    final raw = await getLyrics(songId);
    if (raw == null || raw.trim().isEmpty) return null;
    return LyricsBundle(lrc: raw);
  }

  // Library
  Future<List<Playlist>> getUserPlaylists();
  Future<List<Song>> getPlaylistDetail(String playlistId);
  Future<List<Song>> getLikedSongs();
  Future<bool> likeSong(String songId, {bool like = true});
  Future<bool> addSongToPlaylist(String playlistId, Song song) async => false;
  Future<Playlist?> createPlaylist(String name) async => null;
  Future<bool> collectPlaylist(String playlistId, {bool collect = true}) async => false;

  // Recommendations
  Future<List<Song>> getDailyRecommendations();

  // Rankings
  //
  // Legacy flat entry point: "the platform's first/default chart".
  //
  // The UI no longer uses it — the chart hub goes through [getToplists] and
  // [getRankedSongs], which expose every chart with ids, metadata and per-track
  // rank/movement. It is kept because the platform probes and several tests use
  // it as a cheap "is the chart plumbing still working" check, and because it
  // is the non-breaking fallback for a platform whose toplist endpoint is not
  // reachable.
  //
  // Do NOT reintroduce a provider around it: the removed `rankingsProvider` was
  // a second, competing chart implementation whose only consumer had already
  // moved to [getToplists] (see docs/mconnect-improvement-plan.md).
  Future<List<Song>> getRankingList();

  // VIP
  Future<VipLevel> getVipStatus();

  // Playlist import
  Future<Playlist?> parseShareLink(String url);

  // ---------------------------------------------------------------------------
  // Capabilities
  //
  // Declared here so the UI stops guessing with `is XxxPlatform` checks and
  // per-page `switch` statements. Defaults are deliberately conservative: a
  // platform that has not implemented something must say so, rather than
  // silently returning an empty list that is indistinguishable from "no data".
  // ---------------------------------------------------------------------------

  /// Whether the platform can produce a "daily recommendation" list at all.
  ///
  /// Opt-in: a platform advertises the feature only once it has a working
  /// source. See [getDailyRecommendation] for the provenance rules.
  bool get supportsDailyRecommendations => false;

  /// Whether the platform supports phone-number + SMS-code login.
  bool get supportsPhoneLogin => false;

  /// Whether the platform exposes artist pages (profile / top songs / albums).
  bool get supportsArtistPage => false;

  /// Whether the platform exposes album pages.
  bool get supportsAlbumPage => false;

  /// Whether the platform exposes a "new songs" listing.
  bool get supportsNewSongs => false;

  // ---------------------------------------------------------------------------
  // Artist / album / new songs / charts
  //
  // Every method defaults to "not supported" so the three adapters keep
  // compiling while they are implemented in parallel. An override must either
  // return real data or throw [UnsupportedActionException] — never return an
  // ambiguous empty list for a capability that simply does not exist.
  // ---------------------------------------------------------------------------

  /// Artist profile (name, avatar, bio, counts). `null` when unavailable.
  Future<Artist?> getArtistDetail(String artistId) async => null;

  /// The artist's most popular songs.
  Future<List<Song>> getArtistTopSongs(
    String artistId, {
    int limit = 50,
  }) async => const [];

  /// Albums released by the artist.
  Future<List<Album>> getArtistAlbums(
    String artistId, {
    int page = 1,
    int limit = 30,
  }) async => const [];

  /// Album metadata (cover, release date, company, genre, description).
  Future<Album?> getAlbumDetail(String albumId) async => null;

  /// Tracks of an album, in track order where the platform reports it.
  Future<List<Song>> getAlbumSongs(String albumId) async => const [];

  /// Newly released songs, optionally filtered by region.
  Future<List<Song>> getNewSongs({
    int limit = 100,
    NewSongRegion region = NewSongRegion.all,
  }) async => const [];

  /// Every chart the platform publishes, grouped however the platform groups
  /// them (QQ: 巅峰榜 / 地区榜 / 特色榜 / 全球榜).
  Future<List<Toplist>> getToplists() async => const [];

  /// Chart contents. [period] only matters for platforms whose charts are
  /// addressed by period (QQ weekly charts).
  Future<List<RankedSong>> getRankedSongs(
    String toplistId, {
    int offset = 0,
    int num = 100,
    String? period,
  }) async => const [];

  // ---------------------------------------------------------------------------
  // Daily recommendations
  // ---------------------------------------------------------------------------

  /// The platform's daily recommendation **plus its provenance**.
  ///
  /// Default: whatever [getDailyRecommendations] returns, with no source
  /// information (the UI then shows no badge). Platforms that personalise the
  /// list — or that fall back to a chart / homepage module — must override
  /// this so the UI can say which promise it is actually keeping.
  Future<RecommendationResult> getDailyRecommendation() async {
    final songs = await getDailyRecommendations();
    return RecommendationResult(songs: songs);
  }
}
