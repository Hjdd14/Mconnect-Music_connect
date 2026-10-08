import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/lyrics/lrclib_client.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

/// W2-A：LRCLIB 兜底（免费、无需 key）。
///
/// 契约形状来自真实响应（`GET /api/search?track_name=&artist_name=` →
/// 对象数组，字段 `duration`(秒) / `instrumental` / `hasWordSync` /
/// `plainLyrics` / `syncedLyrics`(LRC)）。测试用自建样本，不落真实歌词正文。
void main() {
  final song = Song(
    id: 'n1',
    platform: PlatformType.netease,
    name: 'Yesterday',
    duration: const Duration(seconds: 125),
    artists: const [Artist(id: 'a1', name: 'The Beatles')],
  );

  group('shouldAskLrclib', () {
    test('asks when the platform gave no lyrics at all', () {
      expect(shouldAskLrclib(null, songDuration: song.duration), isTrue);
      expect(
        shouldAskLrclib(const LyricsDocument(), songDuration: song.duration),
        isTrue,
      );
    });

    test('does not ask when the platform lyrics look fine', () {
      const document = LyricsDocument(
        lines: [
          LyricsLine(timestamp: Duration(seconds: 5), text: 'a'),
          LyricsLine(timestamp: Duration(seconds: 60), text: 'b'),
        ],
        format: LyricsFormat.lrc,
      );

      expect(
        shouldAskLrclib(document, songDuration: song.duration),
        isFalse,
      );
    });

    test('asks when the timeline is obviously off', () {
      // 最后一行的位置比整首歌还晚半分钟以上：时间轴明显不对。
      const document = LyricsDocument(
        lines: [LyricsLine(timestamp: Duration(minutes: 9), text: 'late')],
        format: LyricsFormat.lrc,
      );

      expect(
        shouldAskLrclib(document, songDuration: song.duration),
        isTrue,
      );
    });

    test('cannot judge a timeline without a song duration', () {
      const document = LyricsDocument(
        lines: [LyricsLine(timestamp: Duration(minutes: 9), text: 'late')],
        format: LyricsFormat.lrc,
      );

      expect(
        shouldAskLrclib(document, songDuration: Duration.zero),
        isFalse,
        reason: '歌长未知时不得凭猜测去兜底',
      );
    });
  });

  group('LrclibClient', () {
    ({LrclibClient client, List<RequestOptions> requests}) build(
      Object? data, {
      int statusCode = 200,
    }) {
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://lrclib.net'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: statusCode,
                data: data,
              ),
            );
          },
        ),
      );
      return (client: LrclibClient(dio: dio), requests: requests);
    }

    Map<String, Object?> candidate({
      required double duration,
      String? synced,
      String? plain = 'words',
      bool instrumental = false,
      bool hasWordSync = false,
    }) {
      return {
        'id': 1,
        'trackName': 'Yesterday',
        'artistName': 'The Beatles',
        'albumName': 'Help!',
        'duration': duration,
        'instrumental': instrumental,
        'hasWordSync': hasWordSync,
        'plainLyrics': plain,
        'syncedLyrics': synced,
      };
    }

    test('returns the synced lyrics of the closest duration', () async {
      final stub = build([
        candidate(duration: 100, synced: '[00:01.00]wrong take'),
        candidate(duration: 124.0, synced: '[00:01.00]right take'),
      ]);

      final lyrics = await stub.client.fetchSyncedLyrics(
        song,
        duration: song.duration,
      );

      expect(lyrics, '[00:01.00]right take');
      final query = stub.requests.single.queryParameters;
      expect(query['track_name'], 'Yesterday');
      expect(query['artist_name'], 'The Beatles');
    });

    test('skips instrumental entries and entries without synced lyrics', () async {
      final stub = build([
        candidate(duration: 125, synced: '[00:01.00]instrumental', instrumental: true),
        candidate(duration: 125, synced: null),
        candidate(duration: 125, synced: '[00:01.00]real one'),
      ]);

      expect(
        await stub.client.fetchSyncedLyrics(song, duration: song.duration),
        '[00:01.00]real one',
      );
    });

    test('rejects a candidate whose duration is far off', () async {
      final stub = build([
        candidate(duration: 400, synced: '[00:01.00]some other song'),
      ]);

      expect(
        await stub.client.fetchSyncedLyrics(song, duration: song.duration),
        isNull,
        reason: '时长差太远宁可不要，也不要把别的歌的歌词贴上来',
      );
    });

    test('accepts the first usable candidate when the duration is unknown', () async {
      final stub = build([
        candidate(duration: 400, synced: '[00:01.00]any'),
      ]);

      expect(
        await stub.client.fetchSyncedLyrics(song, duration: Duration.zero),
        '[00:01.00]any',
      );
    });

    test('a 404 (no match) is a miss, not a crash', () async {
      final stub = build(null, statusCode: 404);

      expect(
        await stub.client.fetchSyncedLyrics(song, duration: song.duration),
        isNull,
      );
    });

    test('malformed bodies are a miss, not a crash', () async {
      final stub = build({'unexpected': 'shape'});

      expect(
        await stub.client.fetchSyncedLyrics(song, duration: song.duration),
        isNull,
      );
    });

    test('an empty result list is a miss', () async {
      final stub = build(const <Object>[]);

      expect(
        await stub.client.fetchSyncedLyrics(song, duration: song.duration),
        isNull,
      );
    });

    test('parses a JSON string body too', () async {
      final stub = build(
        '[{"duration":125.0,"instrumental":false,'
        '"syncedLyrics":"[00:01.00]from string"}]',
      );

      expect(
        await stub.client.fetchSyncedLyrics(song, duration: song.duration),
        '[00:01.00]from string',
      );
    });
  });
}
