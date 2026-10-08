import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/features/player/presentation/providers/lyrics_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/platform/base/music_platform.dart';

/// W2-A：歌词缓存 TTL + 清理入口。
///
/// `LyricsCache.syncedAt` 一直是**只写不读**的死字段：缓存一旦写入就永远命中，
/// 平台的歌词修订（错别字、时间轴修正）再也没有机会被取回。这里把 TTL 定成
/// 一个可注入的纯策略，并给清理入口一个可测的实现。
void main() {
  final song = _song('netease-1');

  group('TTL policy', () {
    test('a row inside the TTL is still fresh', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final syncedAt =
          now.millisecondsSinceEpoch - lyricsCacheTtl.inMilliseconds + 1;

      expect(isLyricsCacheExpired(syncedAt, now: now), isFalse);
    });

    test('a row exactly at the TTL boundary is expired', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final syncedAt =
          now.millisecondsSinceEpoch - lyricsCacheTtl.inMilliseconds;

      expect(isLyricsCacheExpired(syncedAt, now: now), isTrue);
    });

    test('a row from the far past and one from the future are handled', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);

      expect(isLyricsCacheExpired(0, now: now), isTrue);
      expect(
        isLyricsCacheExpired(now.millisecondsSinceEpoch + 60000, now: now),
        isFalse,
        reason: '时钟回拨/未来时间戳不得判成过期（否则每次播放都重取）',
      );
    });
  });

  group('resolveLyricsForSong', () {
    test('serves a cached row that is still inside the TTL', () async {
      final platform = _FakeLyricsPlatform(
        PlatformType.netease,
        lyrics: {'netease-1': '[00:01.00]网络版'},
      );
      final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);

      final document = await resolveLyricsForSong(
        song: song,
        platforms: [platform],
        cachedLyrics: (content: '[00:01.00]缓存版', format: 'lrc'),
        cachedSyncedAt: now.millisecondsSinceEpoch - 1000,
        now: () => now,
      );

      expect(document!.lines.single.text, '缓存版');
      expect(platform.requestedLyrics, isEmpty);
    });

    test('refetches when the cached row is older than the TTL', () async {
      final platform = _FakeLyricsPlatform(
        PlatformType.netease,
        lyrics: {'netease-1': '[00:01.00]网络版'},
      );
      final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);

      final document = await resolveLyricsForSong(
        song: song,
        platforms: [platform],
        cachedLyrics: (content: '[00:01.00]缓存版', format: 'lrc'),
        cachedSyncedAt:
            now.millisecondsSinceEpoch - lyricsCacheTtl.inMilliseconds,
        now: () => now,
      );

      expect(document!.lines.single.text, '网络版');
      expect(platform.requestedLyrics, ['netease-1']);
    });

    test('a cached row with an unknown age is still served', () async {
      // Backward compatibility: rows written before `syncedAt` was read (and
      // callers that do not pass one) must behave exactly as before.
      final platform = _FakeLyricsPlatform(
        PlatformType.netease,
        lyrics: {'netease-1': '[00:01.00]网络版'},
      );

      final document = await resolveLyricsForSong(
        song: song,
        platforms: [platform],
        cachedLyrics: (content: '[00:01.00]缓存版', format: 'lrc'),
      );

      expect(document!.lines.single.text, '缓存版');
      expect(platform.requestedLyrics, isEmpty);
    });
  });

  group('purgeExpiredLyricsCache', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> insert(
      String songId,
      int syncedAt, {
      String platform = 'netease',
    }) {
      return db
          .into(db.lyricsCache)
          .insert(
            LyricsCacheCompanion.insert(
              songId: songId,
              platform: platform,
              content: '[00:01.00]$songId',
              format: 'lrc',
              syncedAt: syncedAt,
            ),
            mode: InsertMode.insertOrReplace,
          );
    }

    test('drops only the expired rows and reports how many went', () async {
      final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final expired =
          now.millisecondsSinceEpoch - lyricsCacheTtl.inMilliseconds - 1;
      final fresh = now.millisecondsSinceEpoch - 1000;
      await insert('old', expired);
      await insert('new', fresh);
      await insert('older', 0, platform: 'qq');

      expect(await purgeExpiredLyricsCache(db: db, now: now), 2);

      expect(await db.lyricsCacheDao.getCachedLyrics('old', 'netease'), isNull);
      expect(await db.lyricsCacheDao.getCachedLyrics('older', 'qq'), isNull);
      expect(
        await db.lyricsCacheDao.getCachedLyrics('new', 'netease'),
        '[00:01.00]new',
      );
    });

    test('is a no-op when everything is fresh', () async {
      final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      await insert('new', now.millisecondsSinceEpoch - 1000);

      expect(await purgeExpiredLyricsCache(db: db, now: now), 0);
      expect(
        await db.lyricsCacheDao.getCachedLyrics('new', 'netease'),
        isNotNull,
      );
    });
  });
}

Song _song(String id) => Song(
  id: id,
  platform: PlatformType.netease,
  name: '晚风',
  duration: const Duration(seconds: 240),
  artists: const [Artist(id: 'artist', name: 'artist')],
);

/// Only `getLyrics` matters for this file; the rest satisfies the interface.
class _FakeLyricsPlatform extends MusicPlatform {
  _FakeLyricsPlatform(this.platformType, {this.lyrics = const {}});

  @override
  final PlatformType platformType;
  final Map<String, String> lyrics;
  final List<String> requestedLyrics = [];

  @override
  String get platformName => platformType.name;

  @override
  bool get isLoggedIn => true;

  @override
  Future<String?> getLyrics(String songId) async {
    requestedLyrics.add(songId);
    return lyrics[songId];
  }

  @override
  Future<List<Song>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async => const [];

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) async => 'https://example.test/$songId.mp3';

  @override
  Future<List<AudioQuality>> getAvailableQualities(String songId) async =>
      const [];

  @override
  Future<QrLoginResult> getQrCode() => throw UnimplementedError();

  @override
  Stream<QrLoginStatus> pollQrStatus(String key) => throw UnimplementedError();

  @override
  Future<LoginResult> loginByPhone(String phone, String code) =>
      throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<User?> getUserInfo() async => null;

  @override
  Future<List<Playlist>> getUserPlaylists() async => const [];

  @override
  Future<List<Song>> getPlaylistDetail(String playlistId) async => const [];

  @override
  Future<List<Song>> getLikedSongs() async => const [];

  @override
  Future<bool> likeSong(String songId, {bool like = true}) async => false;

  @override
  Future<List<Song>> getDailyRecommendations() async => const [];

  @override
  Future<List<Song>> getRankingList() async => const [];

  @override
  Future<VipLevel> getVipStatus() async => VipLevel.free;

  @override
  Future<Playlist?> parseShareLink(String url) async => null;
}
