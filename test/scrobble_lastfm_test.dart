import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/scrobble/data/lastfm_compatible_backend.dart';
import 'package:mconnect/features/scrobble/domain/scrobble_backend.dart';
import 'package:mconnect/features/scrobble/domain/scrobble_rules.dart';

/// Captures the request a backend makes and answers with a canned body.
///
/// The transport is the thing under test, so the assertion that matters is the
/// **wire shape**: the form keys with their array notation, the signature over
/// exactly those keys, and the absence of the fields that must not be sent.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({
    this.statusCode = 200,
    this.body = '{"user":{}}',
    Map<String, List<String>>? headers,
  }) : headers = headers ?? const {};

  final int statusCode;
  final String body;
  final Map<String, List<String>> headers;
  final List<RequestOptions> requests = [];

  String get _lastBody {
    final request = requests.last;
    final data = request.data;
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
    if (data is Map) {
      // The wire form depends on the **content type**, not on the Dart type:
      // ListenBrainz posts JSON while this transport posts a urlencoded form —
      // and both arrive here as a `Map`. Encoding by Dart type alone turned the
      // form into JSON, which `Uri.splitQueryString` then parsed as a single
      // key with an empty value.
      final contentType = (request.contentType ?? '').toLowerCase();
      if (contentType.contains('json')) return jsonEncode(data);
      return data.entries
          .map(
            (e) =>
                '${Uri.encodeQueryComponent('${e.key}')}='
                '${Uri.encodeQueryComponent('${e.value}')}',
          )
          .join('&');
    }
    return '${data ?? ''}';
  }

  /// The form-encoded body as `key -> value`.
  Map<String, String> get lastForm => Uri.splitQueryString(_lastBody);

  /// The JSON body as a map.
  Map<String, dynamic> get lastJson =>
      Map<String, dynamic>.from(jsonDecode(_lastBody) as Map);

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
  String artist = 'Radiohead',
  String track = 'Karma Police',
  int playedAtSeconds = 1718150400,
  String? album,
  int? trackNumber,
  int? durationSeconds,
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
  );
}

({LastFmCompatibleBackend backend, _RecordingAdapter adapter}) _build({
  int statusCode = 200,
  String body = '{"user":{}}',
  Map<String, List<String>>? headers,
  String apiKey = 'KEY',
  String apiSecret = 'SECRET',
  String sessionKey = 'SK',
}) {
  final adapter = _RecordingAdapter(
    statusCode: statusCode,
    body: body,
    headers: headers,
  );
  final dio = Dio()..httpClientAdapter = adapter;
  return (
    backend: LastFmCompatibleBackend(
      id: 'lastfm',
      displayName: 'Last.fm',
      apiKey: apiKey,
      apiSecret: apiSecret,
      sessionKey: sessionKey,
      dio: dio,
    ),
    adapter: adapter,
  );
}

void main() {
  group('lastFmApiSig', () {
    // The expected digests are computed from the published rule
    // ("sort by name, concatenate name+value, append the shared secret, MD5
    // lowercase hex") by an independent tool, so this is a real vector rather
    // than a restatement of the implementation.
    const params = <String, String>{
      'method': 'track.scrobble',
      'api_key': 'KEY',
      'sk': 'SK',
      'artist[0]': 'Radiohead',
      'track[0]': 'Karma Police',
      'timestamp[0]': '1718150400',
    };

    test('matches the published algorithm on a real parameter set', () {
      expect(lastFmApiSig(params, 'SECRET'), '67ddd48cac139cb9274762043f76e12b');
    });

    test('excludes format, callback and api_sig from the signature', () {
      final withExtras = <String, String>{
        ...params,
        'format': 'json',
        'callback': 'cb',
        'api_sig': 'whatever-the-caller-passed',
      };
      expect(
        lastFmApiSig(withExtras, 'SECRET'),
        lastFmApiSig(params, 'SECRET'),
      );
    });

    test('sorts array-notation keys as plain strings', () {
      // `artist[10]` sorts **before** `artist[2]` (and before `artist[1]`),
      // because `]` is 0x5D and `0` is 0x30. Last.fm re-computes the signature
      // with the same rule, so "fixing" the order would break every batch.
      final batch = <String, String>{
        'method': 'track.scrobble',
        'api_key': 'KEY',
        'sk': 'SK',
        'artist[0]': 'A0',
        'artist[1]': 'A1',
        'artist[2]': 'A2',
        'artist[10]': 'A10',
      };
      final sorted = batch.keys
          .where((k) => k != 'format' && k != 'callback' && k != 'api_sig')
          .toList()
        ..sort();
      expect(sorted, [
        'api_key',
        'artist[0]',
        'artist[10]',
        'artist[1]',
        'artist[2]',
        'method',
        'sk',
      ]);
      expect(lastFmApiSig(batch, 'SECRET'), '4ddf38c19dec1edb9d9ac4d00a8ed7a9');
    });

    test('signs the now-playing set, which has no timestamp', () {
      final nowPlaying = <String, String>{
        'method': 'track.updateNowPlaying',
        'api_key': 'KEY',
        'sk': 'SK',
        'artist': 'Radiohead',
        'track': 'Karma Police',
        'duration': '264',
      };
      expect(
        lastFmApiSig(nowPlaying, 'SECRET'),
        'd86a82d33d1e1c9706ea791017abedd4',
      );
    });

    test('is sensitive to the exact spelling of a value', () {
      // The int/spelling trap: signing `8` while sending `08` (or vice versa)
      // produces a valid-looking signature the server rejects with code 13.
      final params8 = <String, String>{...params, 'trackNumber': '8'};
      final params08 = <String, String>{...params, 'trackNumber': '08'};
      expect(
        lastFmApiSig(params8, 'SECRET'),
        isNot(lastFmApiSig(params08, 'SECRET')),
      );
    });
  });

  group('shouldScrobble', () {
    test('rejects a track of 30 seconds or less', () {
      expect(
        shouldScrobble(
          actualPlayed: const Duration(seconds: 30),
          trackDuration: const Duration(seconds: 30),
        ),
        isFalse,
      );
    });

    test('needs half the track when that is under four minutes', () {
      // 31s track -> half is 15.5s.
      expect(
        shouldScrobble(
          actualPlayed: const Duration(milliseconds: 15000),
          trackDuration: const Duration(seconds: 31),
        ),
        isFalse,
      );
      expect(
        shouldScrobble(
          actualPlayed: const Duration(milliseconds: 15500),
          trackDuration: const Duration(seconds: 31),
        ),
        isTrue,
      );
    });

    test('caps the requirement at four minutes for a long track', () {
      // 10 minutes: half would be 5 minutes, but the cap is 4.
      expect(
        shouldScrobble(
          actualPlayed: const Duration(minutes: 4) - const Duration(seconds: 1),
          trackDuration: const Duration(minutes: 10),
        ),
        isFalse,
      );
      expect(
        shouldScrobble(
          actualPlayed: const Duration(minutes: 4),
          trackDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );
    });
  });

  group('LastFmCompatibleBackend', () {
    test('submits a batch as one signed form with array notation', () async {
      final env = _build(
        body:
            '{"scrobbles":{"@attr":{"accepted":"2","ignored":"0"}}}',
      );

      final result = await env.backend.scrobble([
        _entry(album: 'OK Computer', trackNumber: 8, durationSeconds: 264),
        _entry(artist: 'Portishead', track: 'Roads', playedAtSeconds: 1718150500),
      ]);

      expect(env.adapter.requests, hasLength(1));
      final form = env.adapter.lastForm;
      expect(form['method'], 'track.scrobble');
      expect(form['api_key'], 'KEY');
      expect(form['sk'], 'SK');
      expect(form['artist[0]'], 'Radiohead');
      expect(form['track[0]'], 'Karma Police');
      expect(form['timestamp[0]'], '1718150400');
      expect(form['album[0]'], 'OK Computer');
      expect(form['trackNumber[0]'], '8');
      expect(form['duration[0]'], '264');
      expect(form['chosenByUser[0]'], '0');
      expect(form['artist[1]'], 'Portishead');
      expect(form['timestamp[1]'], '1718150500');
      expect(form['format'], 'json');
      // Signed over exactly what is sent; `format`/`api_sig` are filtered by the
      // signature function itself, so the whole form can be handed to it.
      expect(form['api_sig'], lastFmApiSig(form, 'SECRET'));
      expect(result.accepted, 2);
      expect(result.retryable, isFalse);

      // A write must be a POST body: the session key never rides in a URL.
      expect(env.adapter.requests.single.uri.query, isEmpty);
      expect(env.adapter.requests.single.method, 'POST');
    });

    test('now-playing has no timestamp and no batch indices', () async {
      final env = _build(body: '{"nowplaying":{}}');

      await env.backend.nowPlaying(
        _entry(album: 'OK Computer', trackNumber: 8, durationSeconds: 264),
      );

      final form = env.adapter.lastForm;
      expect(form['method'], 'track.updateNowPlaying');
      expect(form['artist'], 'Radiohead');
      expect(form['track'], 'Karma Police');
      expect(form['album'], 'OK Computer');
      expect(form['trackNumber'], '8');
      // "now playing" is not a listen: no timestamp, and no array notation.
      expect(form.containsKey('timestamp'), isFalse);
      expect(form.keys.where((key) => key.contains('[')), isEmpty);
      expect(form['api_sig'], lastFmApiSig(form, 'SECRET'));
    });

    test('refuses an oversized batch without touching the network', () async {
      final env = _build();
      final entries = [
        for (var i = 0; i <= kLastFmMaxBatch; i++)
          _entry(track: 'track-$i', playedAtSeconds: 1718150400 + i),
      ];

      final result = await env.backend.scrobble(entries);

      expect(result.fatal, isTrue);
      expect(result.message, contains('$kLastFmMaxBatch'));
      expect(env.adapter.requests, isEmpty);
    });

    test('maps Last.fm error codes onto fatal, retryable and dropped', () async {
      // 13: invalid method signature — our bug, retrying cannot help.
      var env = _build(body: '{"error":13,"message":"Invalid method signature"}');
      var result = await env.backend.scrobble([_entry()]);
      expect(result.fatal, isTrue);
      expect(result.retryable, isFalse);
      expect(env.backend.lastError, contains('签名'));

      // 9: the user revoked or the session expired.
      env = _build(body: '{"error":9,"message":"Invalid session key"}');
      result = await env.backend.scrobble([_entry()]);
      expect(result.fatal, isTrue);
      expect(env.backend.lastError, contains('重新登录'));

      // 26: the application itself is suspended.
      env = _build(body: '{"error":26}');
      result = await env.backend.scrobble([_entry()]);
      expect(result.fatal, isTrue);

      // 29: rate limited — retryable, and never sooner than the 30s floor.
      env = _build(body: '{"error":29,"message":"Rate limit exceeded"}');
      result = await env.backend.scrobble([_entry()]);
      expect(result.retryable, isTrue);
      expect(result.fatal, isFalse);
      expect(result.retryAfter, kRateLimitFloor);

      // 16: temporary outage — retryable on the outbox's own backoff.
      env = _build(body: '{"error":16}');
      result = await env.backend.scrobble([_entry()]);
      expect(result.retryable, isTrue);
      expect(result.retryAfter, isNull);

      // 6: bad parameters — settle this entry instead of wedging the queue.
      env = _build(body: '{"error":6}');
      result = await env.backend.scrobble([_entry()]);
      expect(result.retryable, isFalse);
      expect(result.fatal, isFalse);
      expect(result.ignored, 1);
    });

    test('reports HTTP 200 with ignored entries instead of success', () async {
      final env = _build(
        body:
            '{"scrobbles":{"@attr":{"accepted":"1","ignored":"1"},'
            '"scrobble":[{"ignoredMessage":{"code":"1"}}]}}',
      );

      final result = await env.backend.scrobble([_entry(), _entry()]);

      // `ignored` arrives as a **string** in Last.fm's JSON, and it is not a
      // failure: those entries are permanently refused, so they are settled.
      expect(result.accepted, 1);
      expect(result.ignored, 1);
      expect(result.fatal, isFalse);
      expect(result.retryable, isFalse);
      expect(env.backend.lastError, contains('忽略'));
    });

    test('honours Retry-After on an HTTP 429', () async {
      final env = _build(
        statusCode: 429,
        body: '{}',
        headers: {'retry-after': const ['45']},
      );

      final result = await env.backend.scrobble([_entry()]);

      expect(result.retryable, isTrue);
      expect(result.retryAfter, const Duration(seconds: 45));
    });

    test('validates the session through user.getInfo', () async {
      var env = _build(body: '{"user":{"name":"listener"}}');
      expect(await env.backend.validate(), isTrue);
      expect(env.adapter.lastForm['method'], 'user.getInfo');
      expect(env.adapter.lastForm['sk'], 'SK');
      expect(env.adapter.lastForm['api_sig'], isNotNull);

      env = _build(body: '{"error":9,"message":"Invalid session key"}');
      expect(await env.backend.validate(), isFalse);
      expect(env.backend.lastError, contains('重新登录'));
    });

    test('stays offline when a credential is missing', () async {
      final env = _build(apiSecret: '');

      expect(env.backend.isConfigured, isFalse);
      expect(await env.backend.validate(), isFalse);
      final result = await env.backend.scrobble([_entry()]);
      expect(result.fatal, isTrue);
      await env.backend.nowPlaying(_entry());
      expect(env.adapter.requests, isEmpty);
    });

    test('one transport serves Libre.fm by base URL alone', () async {
      final adapter = _RecordingAdapter(
        body: '{"scrobbles":{"@attr":{"accepted":"1"}}}',
      );
      final dio = Dio()..httpClientAdapter = adapter;
      // Only the id, the label and the base URL differ from Last.fm.
      final backend = LastFmCompatibleBackend(
        id: 'librefm',
        displayName: 'Libre.fm',
        apiKey: 'LIBRE-KEY',
        apiSecret: 'LIBRE-SECRET',
        sessionKey: 'SK',
        dio: dio,
        baseUrl: kLibreFmBaseUrl,
      );

      await backend.scrobble([_entry()]);

      expect(backend.id, 'librefm');
      expect(adapter.requests.single.uri.toString(), kLibreFmBaseUrl);
      expect(adapter.lastForm['sk'], 'SK');
      expect(adapter.lastForm['api_sig'], isNotNull);
    });
  });
}
