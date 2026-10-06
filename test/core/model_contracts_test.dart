import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/models/album.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

/// Contract tests for the models and helpers frozen in Wave 0 of the v1.4.0
/// plan. These are pure functions with no I/O, so they are cheap and they pin
/// the behaviour the rest of the app (and the platform adapters) relies on.
void main() {
  group('PlatformType.tryParse / parse', () {
    test('every enum value round-trips through its name', () {
      for (final type in PlatformType.values) {
        expect(PlatformType.tryParse(type.name), type);
        expect(PlatformType.parse(type.name), type);
      }
    });

    test('an unknown or missing name is null, not a silent default', () {
      // This replaces eight `orElse: () => PlatformType.netease` sites that
      // re-attributed unknown data to NetEase instead of reporting it.
      expect(PlatformType.tryParse('spotify'), isNull);
      expect(PlatformType.tryParse(''), isNull);
      expect(PlatformType.tryParse(null), isNull);
      // Case matters: these are persisted identifiers, not display names.
      expect(PlatformType.tryParse('NetEase'), isNull);
    });

    test('parse throws where an unknown platform is a programming error', () {
      expect(
        () => PlatformType.parse('spotify'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Song.dedupeKey', () {
    Song song(
      String name, {
      String artist = '歌手',
      Duration duration = const Duration(seconds: 200),
      String id = 'a',
      PlatformType platform = PlatformType.netease,
    }) => Song(
      id: id,
      platform: platform,
      name: name,
      artists: [Artist(id: 'ar-1', name: artist)],
      duration: duration,
    );

    test('the same recording matches across platforms', () {
      final a = song('甲乙丙丁', id: 'n1', platform: PlatformType.netease);
      final b = song('甲乙丙丁', id: 'q1', platform: PlatformType.qq);
      expect(a.dedupeKey, b.dedupeKey);
    });

    test('variant markers in brackets are stripped', () {
      final plain = song('甲乙丙丁');
      for (final variant in const [
        '甲乙丙丁 (Live)',
        '甲乙丙丁（现场版）',
        '甲乙丙丁 (feat. 李佳薇)',
        '甲乙丙丁 (Remastered)',
        '甲乙丙丁（重制版）',
        '甲乙丙丁 - Live',
        '甲乙丙丁 - Remastered 2011',
      ]) {
        expect(
          song(variant).dedupeKey,
          plain.dedupeKey,
          reason: '$variant should collapse onto the plain title',
        );
      }
    });

    test('a different song does not collapse', () {
      expect(song('甲乙丙丁').dedupeKey, isNot(song('丙丁甲乙').dedupeKey));
      expect(
        song('甲乙丙丁').dedupeKey,
        isNot(song('甲乙丙丁', artist: '别人').dedupeKey),
      );
    });

    test('only the primary artist is used', () {
      final primary = song('歌', artist: '主唱');
      final withFeat = Song(
        id: 'x',
        platform: PlatformType.qq,
        name: '歌',
        artists: const [
          Artist(id: 'a', name: '主唱'),
          Artist(id: 'b', name: '嘉宾'),
        ],
        duration: const Duration(seconds: 200),
      );
      expect(withFeat.dedupeKey, primary.dedupeKey);
    });

    test('duration is bucketed into 4s, so the tolerance is ±2s at best', () {
      // Buckets are `round(seconds / 4)`, i.e. boundaries are exclusive: 200s
      // and 204s land in buckets 50 and 51, while 200s and 201s share one.
      // Two durations up to 4s apart can therefore straddle a boundary and be
      // treated as different songs - acceptable for a best-effort merge, and
      // pinned here so the intent is not mistaken for "always ±2s".
      final base = song('歌', duration: const Duration(seconds: 200));
      expect(
        song('歌', duration: const Duration(seconds: 201)).dedupeKey,
        base.dedupeKey,
      );
      expect(
        song('歌', duration: const Duration(seconds: 204)).dedupeKey,
        isNot(base.dedupeKey),
      );
    });

    test('an unknown duration does not merge everything', () {
      final unknownA = song('甲', duration: Duration.zero);
      final unknownB = song('乙', duration: Duration.zero);
      expect(unknownA.dedupeKey, isNot(unknownB.dedupeKey));
    });

    test('fingerprint keeps its original, stricter meaning', () {
      // `fingerprint` is persisted, so its format must not drift with
      // dedupeKey's looser matching.
      final s = song('歌', artist: '主唱', duration: const Duration(seconds: 61));
      expect(s.fingerprint, '歌_主唱_61');
      expect(s.dedupeKey, isNot(contains('_')));
    });
  });

  group('Album / Artist serialisation', () {
    test('Album round-trips every v1.4.0 field', () {
      final album = Album(
        id: 'al-1',
        name: '未完成',
        artistName: '孙燕姿',
        coverUrl: 'https://example.test/c.jpg',
        releaseDate: DateTime(2003, 1, 10),
        artistId: 'ar-9',
        description: '简介',
        songCount: 11,
        company: '华纳唱片',
        genre: 'Pop 流行',
        language: '国语',
      );

      final restored = Album.fromJson(album.toJson());
      expect(restored.id, 'al-1');
      expect(restored.name, '未完成');
      expect(restored.artistId, 'ar-9');
      expect(restored.songCount, 11);
      expect(restored.company, '华纳唱片');
      expect(restored.genre, 'Pop 流行');
      expect(restored.language, '国语');
      expect(restored.releaseDate, DateTime(2003, 1, 10));
    });

    test('Album accepts a millisecond publish time', () {
      // 网易云/QQ report publish dates as epoch milliseconds.
      final album = Album.fromJson({
        'id': 'al-2',
        'name': '专辑',
        'releaseDate': DateTime(2003, 1, 10).millisecondsSinceEpoch,
      });
      expect(album.releaseDate, DateTime(2003, 1, 10));
    });

    test('Album.copyWith only replaces what is passed', () {
      const album = Album(id: 'a', name: 'n', songCount: 3);
      expect(album.copyWith(name: 'n2').songCount, 3);
      expect(album.copyWith(songCount: 9).name, 'n');
    });

    test('Artist round-trips every v1.4.0 field', () {
      const artist = Artist(
        id: 'ar-1',
        name: '陈奕迅',
        avatarUrl: 'https://example.test/a.jpg',
        briefDesc: '简介',
        songCount: 1400,
        albumCount: 103,
        fansCount: 12,
      );

      final restored = Artist.fromJson(artist.toJson());
      expect(restored.id, 'ar-1');
      expect(restored.name, '陈奕迅');
      expect(restored.avatarUrl, 'https://example.test/a.jpg');
      expect(restored.briefDesc, '简介');
      expect(restored.songCount, 1400);
      expect(restored.albumCount, 103);
      expect(restored.fansCount, 12);
    });

    test('Artist tolerates numeric strings from the platforms', () {
      final artist = Artist.fromJson({
        'id': 42,
        'name': 'X',
        'songCount': '7',
        'albumCount': '3',
      });
      expect(artist.id, '42');
      expect(artist.songCount, 7);
      expect(artist.albumCount, 3);
      expect(artist.fansCount, isNull);
    });
  });

  group('Song v1.4.0 fields', () {
    test('carry the album/artist ids used by the album and artist pages', () {
      const song = Song(
        id: 's1',
        platform: PlatformType.qq,
        name: '我不难过',
        artists: [Artist(id: 'ar-1', name: '孙燕姿')],
        albumId: 'al-1',
        artistId: 'ar-1',
        trackNumber: 1,
        fee: 1,
      );

      expect(song.albumId, 'al-1');
      expect(song.artistId, 'ar-1');
      expect(song.trackNumber, 1);
      expect(song.fee, 1);
      // Equality is still (id, platform): several places rely on that.
      const same = Song(
        id: 's1',
        platform: PlatformType.qq,
        name: '名字变了',
        artists: [],
      );
      expect(song, same);
      expect(song.hashCode, same.hashCode);
    });

    test('equal songs with different metadata still dedupe identically', () {
      const a = Song(
        id: 's1',
        platform: PlatformType.netease,
        name: '歌',
        artists: [Artist(id: 'x', name: '歌手')],
      );
      const b = Song(
        id: 's2',
        platform: PlatformType.kugou,
        name: '歌',
        artists: [Artist(id: 'y', name: '歌手')],
      );
      expect(a.dedupeKey, b.dedupeKey);
      expect(a, isNot(b), reason: 'identity is still per-platform');
      expect(AudioLevel.lossless.isLossless, isTrue);
    });
  });
}
