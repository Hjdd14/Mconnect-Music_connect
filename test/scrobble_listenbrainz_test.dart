import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/scrobble/data/listenbrainz_native_backend.dart';
import 'package:mconnect/features/scrobble/domain/scrobble_backend.dart';
import 'package:mconnect/features/scrobble/domain/scrobble_rules.dart';

/// Captures the request a backend makes and answers with a canned body.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({
    this.statusCode = 200,
    this.body = '{"status":"ok"}',
    Map<String, List<String>>? headers,
  }) : headers = headers ?? const {};

  final int statusCode;
  final String body;
  final Map<String, List<String>> headers;
  final List<RequestOptions> requests = [];

  String get _lastBody {
    final data = requests.last.data;
    if (data is String) return data;
    if (data is List<int>) return utf8.decode(data);
    if (data is FormData) {
      // Dio does NOT encode FormData for us: the adapter sees the raw FormData,
      // so reproduce the wire form here (the assertions are about the wire
      // shape, and `Uri.splitQueryString` decodes `%5B` back to `[`).
      return data.fields
          .map(
            (e) =>
                '${Uri.encodeQueryComponent(e.key)}='
                '${Uri.encodeQueryComponent(e.value)}',
          )
          .join('&');
    }
    // ListenBrainz submissions are JSON: encode the Map rather than falling back
    // to Dart's `toString()`, which is not JSON at all.
    if (data is Map) return jsonEncode(data);
    return '${data ?? ''}';
  }

  Map<String, dynamic> get lastJson =>
      Map<String, dynamic>.from(jsonDecode(_lastBody) as Map);

  Map<String, String> get lastForm => Uri.splitQueryString(_lastBody);

  /// The single payload entry of the last submission.
  Map<String, dynamic> get lastPayload =>
      Map<String, dynamic>.from((lastJson['payload'] as List).first as Map);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: const ['application/json'],
        ...headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ScrobbleEntry _entry({
  String artist = 'Rick Astley',
  String track = 'Never Gonna Give You Up',
  int playedAtSeconds = 1443521965,
  String? album,
  int? trackNumber,
  int? durationSeconds,
  String? originUrl,
}) {
  return ScrobbleEntry(
    artist: artist,
    track: track,
    playedAt: DateTime.fromMillisecondsSinceEpoch(
      playedAtSeconds * 1000,
      isUtc: true,
    ),
    album: album,
    trackNumber: trackNumber,
    durationSeconds: durationSeconds,
    originUrl: originUrl,
  );
}

({ListenBrainzNativeBackend backend, _RecordingAdapter adapter}) _build({
  int statusCode = 200,
  String body = '{"status":"ok"}',
  Map<String, List<String>>? headers,
  String token = 'USER-TOKEN',
  String baseUrl = kListenBrainzBaseUrl,
}) {
  final adapter = _RecordingAdapter(
    statusCode: statusCode,
    body: body,
    headers: headers,
  );
  final dio = Dio()..httpClientAdapter = adapter;
  return (
    backend: ListenBrainzNativeBackend(
      id: 'listenbrainz',
      displayName: 'ListenBrainz',
      token: token,
      userAgentContact: 'https://github.com/mconnect',
      dio: dio,
      baseUrl: baseUrl,
    ),
    adapter: adapter,
  );
}

void main() {
  group('ListenBrainz limits', () {
    test('the constants the server enforces are the documented ones', () {
      expect(kListenBrainzMaxListensPerRequest, 1000);
      expect(kListenBrainzMaxPayloadBytes, 10240000);
      expect(kListenBrainzMaxListenBytes, 10240);
      expect(kListenMinimumTs, 1033430400);
      // "no more than one call per second per client" — the pump's serial gap.
      expect(kScrobblePumpInterval, const Duration(milliseconds: 1200));
      expect(kScrobblePumpInterval.inMilliseconds, greaterThanOrEqualTo(1000));
      // The batch size both backends share.
      expect(kListenBrainzMaxBatch, 50);
      expect(kLastFmMaxBatch, 50);
    });
  });

  group('ListenBrainzNativeBackend', () {
    test('playing_now carries no listened_at', () async {
      final env = _build();

      await env.backend.nowPlaying(_entry(durationSeconds: 222));

      final body = env.adapter.lastJson;
      expect(body['listen_type'], 'playing_now');
      expect((body['payload'] as List), hasLength(1));
      // The server rejects the request outright when the field is present: a
      // now-playing report is temporary state, not a listen.
      expect(env.adapter.lastPayload.containsKey('listened_at'), isFalse);
      expect(
        (env.adapter.lastPayload['track_metadata'] as Map)['track_name'],
        'Never Gonna Give You Up',
      );
    });

    test('single for one listen, import for a backfill, both timed', () async {
      var env = _build();
      await env.backend.scrobble([_entry()]);
      expect(env.adapter.lastJson['listen_type'], 'single');
      expect(env.adapter.lastPayload['listened_at'], 1443521965);

      env = _build();
      final result = await env.backend.scrobble([
        _entry(),
        _entry(playedAtSeconds: 1443522000, track: 'second'),
        _entry(playedAtSeconds: 1443522100, track: 'third'),
      ]);
      final body = env.adapter.lastJson;
      expect(body['listen_type'], 'import');
      final payload = body['payload'] as List;
      expect(payload, hasLength(3));
      for (final item in payload) {
        // Backfill must keep each entry's original play time, never "now".
        expect((item as Map).containsKey('listened_at'), isTrue);
      }
      expect(result.accepted, 3);
    });

    test('sends the required User-Agent and the token header', () async {
      final env = _build();

      await env.backend.scrobble([_entry()]);

      final headers = env.adapter.requests.single.headers;
      expect(headers['Authorization'], 'Token USER-TOKEN');
      // ListenBrainz bans clients that omit the User-Agent, silently.
      expect(headers['User-Agent'], 'Mconnect/1.5.0 ( https://github.com/mconnect )');
      // The token must never be put in the URL.
      expect(env.adapter.requests.single.uri.query, isEmpty);
    });

    test('validate-token also carries the User-Agent', () async {
      final env = _build(body: '{"valid":true,"user_name":"abc"}');

      expect(await env.backend.validate(), isTrue);

      final request = env.adapter.requests.single;
      expect(request.uri.path, '/1/validate-token');
      expect(request.headers['User-Agent'], contains('Mconnect/'));
      expect(request.headers['Authorization'], 'Token USER-TOKEN');
    });

    test('clamps a play time older than the server floor', () async {
      final env = _build();

      // 2000-01-01, i.e. before LISTEN_MINIMUM_TS: a restored queue or a wrong
      // device clock must not turn into a permanently rejected row.
      await env.backend.scrobble([_entry(playedAtSeconds: 946684800)]);

      expect(env.adapter.lastPayload['listened_at'], kListenMinimumTs);
    });

    test('maps the track metadata the way the docs show', () async {
      final env = _build();

      await env.backend.scrobble([
        _entry(
          album: 'Whenever you need somebody',
          trackNumber: 7,
          durationSeconds: 222,
          originUrl: 'https://music.163.com/#/song?id=1',
        ),
      ]);

      final metadata = Map<String, dynamic>.from(
        env.adapter.lastPayload['track_metadata'] as Map,
      );
      expect(metadata['artist_name'], 'Rick Astley');
      expect(metadata['track_name'], 'Never Gonna Give You Up');
      expect(metadata['release_name'], 'Whenever you need somebody');
      final info = Map<String, dynamic>.from(metadata['additional_info'] as Map);
      expect(info['duration_ms'], 222000);
      expect(info['media_player'], 'Mconnect');
      expect(info['submission_client'], 'Mconnect');
      expect(info['origin_url'], 'https://music.163.com/#/song?id=1');
      // `tracknumber` is a string in the documented shape, duration is ms.
      expect(info['tracknumber'], '7');
    });

    test('a 401 is fatal and names the fix', () async {
      final env = _build(statusCode: 401, body: '{"code":401}');

      final result = await env.backend.scrobble([_entry()]);

      expect(result.fatal, isTrue);
      expect(result.retryable, isFalse);
      expect(env.backend.lastError, contains('token'));
    });

    test('a 400 is settled rather than retried', () async {
      final env = _build(statusCode: 400, body: '{"code":400}');

      final result = await env.backend.scrobble([_entry()]);

      expect(result.fatal, isFalse);
      expect(result.retryable, isFalse);
      expect(result.message, contains('400'));
    });

    test('a 429 waits the seconds the server asked for', () async {
      final env = _build(
        statusCode: 429,
        body: '{}',
        headers: {'x-ratelimit-reset-in': const ['42']},
      );

      final result = await env.backend.scrobble([_entry()]);

      expect(result.retryable, isTrue);
      expect(result.retryAfter, const Duration(seconds: 42));
    });

    test('a 5xx is retryable and an unparseable body is not fatal', () async {
      var env = _build(statusCode: 503, body: 'nope');
      var result = await env.backend.scrobble([_entry()]);
      expect(result.retryable, isTrue);
      expect(result.fatal, isFalse);

      env = _build(body: 'not json at all');
      result = await env.backend.scrobble([_entry()]);
      expect(result.retryable, isTrue);
      expect(result.fatal, isFalse);
    });

    test('refuses to exceed the server ceiling without a request', () async {
      final env = _build();
      final entries = [
        for (var i = 0; i <= kListenBrainzMaxListensPerRequest; i++)
          _entry(track: 'track-$i', playedAtSeconds: 1443521965 + i),
      ];

      final result = await env.backend.scrobble(entries);

      expect(result.fatal, isTrue);
      expect(env.adapter.requests, isEmpty);
    });

    test('stays offline without a token', () async {
      final env = _build(token: '');

      expect(env.backend.isConfigured, isFalse);
      expect(await env.backend.validate(), isFalse);
      final result = await env.backend.scrobble([_entry()]);
      expect(result.fatal, isTrue);
      await env.backend.nowPlaying(_entry());
      expect(env.adapter.requests, isEmpty);
    });

    test('an invalid token is reported by validate-token', () async {
      var env = _build(body: '{"valid":false}');
      expect(await env.backend.validate(), isFalse);
      expect(env.backend.lastError, contains('token'));

      env = _build(statusCode: 401, body: '{}');
      expect(await env.backend.validate(), isFalse);
      expect(env.backend.lastError, contains('token'));
    });

    test('one transport serves Maloja by base URL alone', () async {
      final env = _build(
        baseUrl: 'https://maloja.example/apis/listenbrainz',
        body: '{"status":"ok"}',
      );

      await env.backend.scrobble([_entry()]);

      expect(
        env.adapter.requests.single.uri.toString(),
        'https://maloja.example/apis/listenbrainz/1/submit-listens',
      );
    });
  });
}
