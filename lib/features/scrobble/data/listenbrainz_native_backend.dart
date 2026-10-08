/// `ListenBrainzNative` transport: `Authorization: Token` header + JSON.
///
/// Serves ListenBrainz and Maloja (the latter through its ListenBrainz-compatible
/// endpoint — Navidrome documents it as a "custom ListenBrainz URL"), A.4.1.
library;

import 'package:dio/dio.dart';

import '../domain/scrobble_backend.dart';
import '../domain/scrobble_rules.dart';

const String kListenBrainzBaseUrl = 'https://api.listenbrainz.org';

class ListenBrainzNativeBackend implements ScrobbleBackend {
  ListenBrainzNativeBackend({
    required this.id,
    required this.displayName,
    required this.token,
    required String userAgentContact,
    String appVersion = '1.5.0',
    Dio? dio,
    this.baseUrl = kListenBrainzBaseUrl,
  }) : _dio = dio ?? Dio(),
       _appVersion = appVersion,
       // ListenBrainz requires a User-Agent of the shape
       // `Application name/<version> ( contact-url )` and **silently bans**
       // clients that omit it (A.3). Sending nothing is not an option, so the
       // contact is a required constructor argument rather than a default that
       // could be forgotten.
       userAgent = 'Mconnect/$appVersion ( $userAgentContact )';

  @override
  final String id;

  @override
  final String displayName;

  /// The user's ListenBrainz user token. **Never** logged: it travels only in
  /// the `Authorization` header, which the redactor also masks as a whole line.
  final String token;

  /// `.../1/submit-listens` lives under this; Maloja instances use their own
  /// prefix (`<instance>/apis/listenbrainz`, to be confirmed on a real instance).
  final String baseUrl;

  final String userAgent;
  final String _appVersion;

  final Dio _dio;

  String? _lastError;

  @override
  String? get lastError => _lastError;

  @override
  int get maxBatchSize => kListenBrainzMaxBatch;

  @override
  bool get isConfigured => token.trim().isNotEmpty;

  @override
  Future<bool> validate() async {
    _lastError = null;
    if (!isConfigured) {
      _lastError = '尚未填写 $displayName 的用户 token';
      return false;
    }
    try {
      final response = await _dio.get<Object?>(
        '$baseUrl/1/validate-token',
        options: Options(headers: _headers, validateStatus: (_) => true),
      );
      final status = response.statusCode ?? 0;
      if (status == 401) {
        _lastError = '$displayName token 无效，请重新粘贴';
        return false;
      }
      if (status >= 400) {
        _lastError = 'HTTP $status';
        return false;
      }
      final body = _asMap(response.data);
      final valid = body?['valid'];
      if (valid == true) return true;
      _lastError = '$displayName token 无效，请重新粘贴';
      return false;
    } on DioException catch (error) {
      _lastError = '网络请求失败：${error.type.name}';
      return false;
    }
  }

  @override
  Future<void> nowPlaying(ScrobbleEntry entry) async {
    if (!isConfigured) return;
    try {
      // `playing_now` payloads must **not** carry `listened_at`: it is a
      // transient state, not a listen (A.3.1 / A.5), and the server rejects the
      // request outright when the field is present.
      await _submit([entry], listenType: 'playing_now');
    } on DioException catch (error) {
      // Transient state: never retried, never queued (A.5).
      _lastError = 'HTTP ${error.response?.statusCode ?? '网络错误'}';
    }
  }

  @override
  Future<ScrobbleResult> scrobble(List<ScrobbleEntry> entries) async {
    if (entries.isEmpty) return ScrobbleResult.ok(accepted: 0);
    if (!isConfigured) return ScrobbleResult.failed('尚未填写 $displayName 的用户 token');
    if (entries.length > kListenBrainzMaxListensPerRequest) {
      return ScrobbleResult.failed(
        '$displayName 单次最多提交 $kListenBrainzMaxListensPerRequest 条，收到 ${entries.length} 条',
      );
    }
    // `single` is exactly one listen; anything else is a backfill, which is what
    // `import` exists for (A.3.1). Both keep each entry's original play time.
    final listenType = entries.length == 1 ? 'single' : 'import';
    try {
      final response = await _submit(entries, listenType: listenType);
      final status = response.statusCode ?? 0;
      if (status == 401) {
        _lastError = '$displayName token 无效，请重新粘贴';
        return ScrobbleResult.failed(_lastError!);
      }
      if (status == 400) {
        // Our payload is malformed — retrying the same bytes cannot help, so the
        // entries are settled rather than left to fail five times.
        _lastError = '$displayName 拒绝了请求（HTTP 400）';
        return ScrobbleResult.permanent(_lastError!, ignored: entries.length);
      }
      if (status == 429) {
        final wait = _rateLimitWait(response) ?? kRateLimitFloor;
        _lastError = '请求过于频繁，${wait.inSeconds} 秒后重试';
        return ScrobbleResult.retry(_lastError!, retryAfter: wait);
      }
      if (status >= 400) {
        _lastError = 'HTTP $status';
        return ScrobbleResult.retry(_lastError!);
      }
      final body = _asMap(response.data);
      if (body != null && body['status'] == 'ok') {
        _lastError = null;
        // The payload is a write confirmation, not a per-listen report: every
        // entry in an accepted request is stored.
        return ScrobbleResult.ok(accepted: entries.length);
      }
      _lastError = '$displayName 返回了无法解析的内容';
      return ScrobbleResult.retry(_lastError!);
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 401) {
        _lastError = '$displayName token 无效，请重新粘贴';
        return ScrobbleResult.failed(_lastError!);
      }
      if (status == 429) {
        final wait = _rateLimitWait(error.response) ?? kRateLimitFloor;
        _lastError = '请求过于频繁，${wait.inSeconds} 秒后重试';
        return ScrobbleResult.retry(_lastError!, retryAfter: wait);
      }
      _lastError = '网络请求失败，稍后自动重试';
      return ScrobbleResult.retry(_lastError!);
    }
  }

  Future<Response<Object?>> _submit(
    List<ScrobbleEntry> entries, {
    required String listenType,
  }) {
    final playingNow = listenType == 'playing_now';
    final payload = [
      for (final entry in entries) _listenPayload(entry, playingNow: playingNow),
    ];
    return _dio.post<Object?>(
      '$baseUrl/1/submit-listens',
      data: {'listen_type': listenType, 'payload': payload},
      options: Options(
        contentType: Headers.jsonContentType,
        headers: _headers,
        validateStatus: (_) => true,
      ),
    );
  }

  Map<String, String> get _headers => {
    'Authorization': 'Token $token',
    'User-Agent': userAgent,
  };

  Map<String, Object?> _listenPayload(
    ScrobbleEntry entry, {
    required bool playingNow,
  }) {
    return {
      // Omitted entirely for `playing_now` — see the call site.
      if (!playingNow) 'listened_at': _listenedAt(entry),
      'track_metadata': {
        'artist_name': entry.artist,
        'track_name': entry.track,
        if (entry.album != null) 'release_name': entry.album,
        'additional_info': {
          'media_player': 'Mconnect',
          'media_player_version': _appVersion,
          'submission_client': 'Mconnect',
          'submission_client_version': _appVersion,
          if (entry.durationSeconds != null)
            'duration_ms': entry.durationSeconds! * 1000,
          if (entry.originUrl != null) 'origin_url': entry.originUrl,
          if (entry.trackNumber != null) 'tracknumber': '${entry.trackNumber}',
        },
      },
    };
  }

  /// Play time, clamped to the server's own floor.
  ///
  /// ListenBrainz rejects anything before [kListenMinimumTs]; a restored queue
  /// or a wrong device clock must not turn that into a permanently failing row.
  int _listenedAt(ScrobbleEntry entry) {
    final seconds = entry.playedAtSeconds;
    return seconds < kListenMinimumTs ? kListenMinimumTs : seconds;
  }

  /// `X-RateLimit-Reset-In` is seconds and is preferred over the absolute
  /// `X-RateLimit-Reset`, because it survives a wrong client clock (A.6).
  static Duration? _rateLimitWait(Response<dynamic>? response) {
    final raw = response?.headers.value('x-ratelimit-reset-in');
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    return seconds == null ? null : Duration(seconds: seconds);
  }

  static Map<String, dynamic>? _asMap(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }
}
