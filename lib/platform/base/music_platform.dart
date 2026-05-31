import '../../models/song.dart';
import '../../models/user.dart';
import '../../models/playlist.dart';
import '../../models/audio_quality.dart';
import '../base/platform_enum.dart';
import '../../core/storage/session_storage.dart';

enum LoginMethod { qrCode, phone }

enum QrLoginStatus { waiting, scanned, success, expired, failed }

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

  const LoginResult({
    required this.success,
    this.user,
    this.cookie,
    this.error,
  });
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
  Future<List<Playlist>> searchPlaylists(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    return const [];
  }

  // Playback
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  });
  Future<List<AudioQuality>> getAvailableQualities(String songId);

  // Lyrics
  Future<String?> getLyrics(String songId);

  // Library
  Future<List<Playlist>> getUserPlaylists();
  Future<List<Song>> getPlaylistDetail(String playlistId);
  Future<List<Song>> getLikedSongs();
  Future<bool> likeSong(String songId, {bool like = true});
  Future<bool> addSongToPlaylist(String playlistId, Song song) async => false;
  Future<Playlist?> createPlaylist(String name) async => null;
  Future<bool> collectPlaylist(
    String playlistId, {
    bool collect = true,
  }) async => false;

  // Recommendations
  Future<List<Song>> getDailyRecommendations();

  // Rankings
  Future<List<Song>> getRankingList();

  // VIP
  Future<VipLevel> getVipStatus();

  // Playlist import
  Future<Playlist?> parseShareLink(String url);
}
