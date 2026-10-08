/// `LastFmCompatible` transport: `api_key` + `api_sig` + `sk`.
///
/// One implementation serves Last.fm, Libre.fm and self-hosted GNU FM — they
/// differ only in base URL and in whose api_key is used (A.4.1). Last.fm is the
/// only one of the three that verifies the signature, which is exactly why the
/// signature is computed here rather than skipped.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../domain/scrobble_backend.dart';
import '../domain/scrobble_rules.dart';

const String kLastFmBaseUrl = 'https://ws.audioscrobbler.com/2.0/';
const String kLibreFmBaseUrl = 'https://libre.fm/2.0/';

class LastFmCompatibleBackend implements ScrobbleBackend {
  LastFmCompatibleBackend({
    required this.id,
    required this.displayName,
    required this.apiKey,
    required this.apiSecret,
    required this.sessionKey,
    Dio? dio,
    this.baseUrl = kLastFmBaseUrl,
    this.userAgent = 'Mconnect',
  }) : _dio = dio ?? Dio();

  @override
  final String id;

  @override
  final String displayName;

  /// Application-level credentials, shipped with the build (A.8 item 3: these
  /// are extractable public credentials, not secrets, and must not be logged).
  final String apiKey;
  final String apiSecret;

  /// The user's session key. **Never** logged, never sent anywhere but the
  /// service that issued it.
  final String sessionKey;

  /// `.../2.0/` of the service; Libre.fm and GNU FM swap this.
  final String baseUrl;

  final String userAgent;

  final Dio _dio;

  String? _lastError;

  @override
  String? get lastError => _lastError;

  @override
  int get maxBatchSize => kLastFmMaxBatch;

  @override
  bool get isConfigured =>
      apiKey.trim().isNotEmpty &&
      apiSecret.trim().isNotEmpty &&
      sessionKey.trim().isNotEmpty;

  @override
  Future<bool> validate() async {
    _lastError = null;
    if (!isConfigured) {
      _lastError = '尚未填写 $displayName 的凭据';
      return false;
    }
    // `user.getInfo` without a `user` parameter answers for the authenticated
    // session, so one read verifies api_key *and* sk and has no side effect.
    final params = <String, String>{
      'method': 'user.getInfo',
      'api_key': apiKey,
      'sk': sessionKey,
    };
    try {
      final body = await _post(params);
      if (body == null) {
        _lastError = '$displayName 返回了无法解析的内容';
        return false;
      }
      final code = _errorCode(body);
      if (code != null) {
        _lastError = lastFmErrorMessage(code);
        return false;
      }
      if (body['user'] is Map) return true;
      _lastError = '$displayName 未返回账号信息';
      return false;
    } on DioException catch (error) {
      _lastError = _networkMessage(error);
      return false;
    }
  }

  @override
  Future<void> nowPlaying(ScrobbleEntry entry) async {
    if (!isConfigured) return;
    // No `timestamp`: a now-playing report is not a listen (A.1.5).
    final params = <String, String>{
      'method': 'track.updateNowPlaying',
      'api_key': apiKey,
      'sk': sessionKey,
      'artist': entry.artist,
      'track': entry.track,
      ..._optionalFields(entry, suffix: ''),
    };
    try {
      final body = await _post(params);
      final code = body == null ? null : _errorCode(body);
      // A failure here is deliberately swallowed: the state is transient, so
      // retrying it would only add noise (A.5).
      _lastError = code == null ? null : lastFmErrorMessage(code);
    } on DioException catch (error) {
      _lastError = _networkMessage(error);
    }
  }

  @override
  Future<ScrobbleResult> scrobble(List<ScrobbleEntry> entries) async {
    if (entries.isEmpty) return ScrobbleResult.ok(accepted: 0);
    if (!isConfigured) return ScrobbleResult.failed('尚未填写 $displayName 的凭据');
    if (entries.length > kLastFmMaxBatch) {
      // The caller is responsible for splitting; failing loudly here beats
      // silently truncating a user's listening history.
      return ScrobbleResult.failed(
        '$displayName 单次最多提交 $kLastFmMaxBatch 条，收到 ${entries.length} 条',
      );
    }

    final params = <String, String>{
      'method': 'track.scrobble',
      'api_key': apiKey,
      'sk': sessionKey,
    };
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      params['artist[$i]'] = entry.artist;
      params['track[$i]'] = entry.track;
      params['timestamp[$i]'] = '${entry.playedAtSeconds}';
      params.addAll(_optionalFields(entry, suffix: '[$i]'));
      // Last.fm treats a missing `chosenByUser` as unknown provenance; these
      // are plays this app observed, not a backfill of someone else's history.
      params['chosenByUser[$i]'] = '0';
    }

    try {
      final body = await _post(params);
      if (body == null) {
        return ScrobbleResult.retry('$displayName 返回了无法解析的内容');
      }
      final code = _errorCode(body);
      if (code != null) {
        final message = lastFmErrorMessage(code);
        _lastError = message;
        return switch (lastFmErrorDisposition(code)) {
          LastFmErrorDisposition.fatal => ScrobbleResult.failed(message),
          LastFmErrorDisposition.retryable => ScrobbleResult.retry(
            message,
            retryAfter: lastFmRetryAfter(code),
          ),
          LastFmErrorDisposition.dropEntry => ScrobbleResult.permanent(
            message,
            // The whole batch was refused, and these entries will never be
            // accepted: settle them so one bad row cannot wedge the queue.
            ignored: entries.length,
          ),
        };
      }

      final attributes = _scrobbleAttributes(body);
      final accepted = attributes.accepted;
      final ignored = attributes.ignored;
      _lastError = ignored > 0
          ? '$ignored 条被 $displayName 忽略'
                '${attributes.ignoredCodes.isEmpty ? '' : '（${attributes.ignoredCodes.join(', ')}）'}'
          : null;
      // HTTP 200 with `ignored > 0` is a normal answer, not a failure: those
      // entries are permanently refused, so they are reported as settled.
      return ScrobbleResult.ok(accepted: accepted, ignored: ignored);
    } on DioException catch (error) {
      final message = _networkMessage(error);
      _lastError = message;
      final status = error.response?.statusCode;
      if (status == 429 || status == 403 || status == 503) {
        return ScrobbleResult.retry(
          message,
          retryAfter: _retryAfterHeader(error.response) ?? kRateLimitFloor,
        );
      }
      // Everything else that is not an API-level error (timeouts, sockets, 4xx
      // this app has not seen) is retryable: losing a listen is worse than
      // retrying one, and the outbox caps attempts on its own.
      return ScrobbleResult.retry(message);
    }
  }

  /// POSTs `params` as a signed form and returns the decoded JSON object.
  ///
  /// `api_sig` is computed over [params] **before** `format` is added, which is
  /// what the specification requires and what the reference implementation does.
  Future<Map<String, dynamic>?> _post(Map<String, String> params) async {
    final form = <String, String>{
      ...params,
      'api_sig': lastFmApiSig(params, apiSecret),
      'format': 'json',
    };
    final response = await _dio.post<Object?>(
      baseUrl,
      data: form,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'User-Agent': userAgent},
        // Last.fm reports almost everything as HTTP 200 + an error code, so the
        // HTTP status is only inspected for the transport-level cases.
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final status = response.statusCode ?? 0;
    if (status >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: 'HTTP $status',
      );
    }
    return _asMap(response.data);
  }

  Map<String, String> _optionalFields(
    ScrobbleEntry entry, {
    required String suffix,
  }) {
    return <String, String>{
      if (entry.album != null) 'album$suffix': entry.album!,
      if (entry.albumArtist != null) 'albumArtist$suffix': entry.albumArtist!,
      if (entry.trackNumber != null) 'trackNumber$suffix': '${entry.trackNumber}',
      if (entry.durationSeconds != null)
        'duration$suffix': '${entry.durationSeconds}',
      if (entry.mbid != null) 'mbid$suffix': entry.mbid!,
    };
  }

  static int? _errorCode(Map<String, dynamic> body) {
    final raw = body['error'];
    if (raw == null) return null;
    return _asInt(raw);
  }

  static ({int accepted, int ignored, List<String> ignoredCodes})
  _scrobbleAttributes(Map<String, dynamic> body) {
    final scrobbles = body['scrobbles'];
    if (scrobbles is! Map) {
      return (accepted: 0, ignored: 0, ignoredCodes: const []);
    }
    final attributes = scrobbles['@attr'];
    final accepted = attributes is Map ? _asInt(attributes['accepted']) ?? 0 : 0;
    final ignored = attributes is Map ? _asInt(attributes['ignored']) ?? 0 : 0;

    final codes = <String>{};
    final entries = scrobbles['scrobble'];
    if (entries is List) {
      for (final item in entries) {
        if (item is! Map) continue;
        final message = item['ignoredMessage'];
        if (message is Map) {
          final code = message['code']?.toString();
          if (code != null && code.isNotEmpty && code != '0') codes.add(code);
        }
      }
    }
    return (accepted: accepted, ignored: ignored, ignoredCodes: codes.toList());
  }

  static Duration? _retryAfterHeader(Response<dynamic>? response) {
    final raw = response?.headers.value('retry-after');
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    return seconds == null ? null : Duration(seconds: seconds);
  }

  static String _networkMessage(DioException error) {
    final status = error.response?.statusCode;
    return status == null
        ? '网络请求失败，稍后自动重试'
        : 'HTTP $status，稍后自动重试';
  }

  static Map<String, dynamic>? _asMap(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.trimLeft().startsWith('{')) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

/// `int` from Last.fm's JSON, which mixes numbers and numeric **strings**
/// (`"@attr":{"accepted":"1"}` is a string on the wire).
int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
