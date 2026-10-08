/// The pure, testable rules shared by the scrobbling transports.
///
/// Everything here is a pure function or a constant: no I/O, no clock, so the
/// two traps the specification calls out (signature string consistency, and the
/// lexicographic order of array-notation keys) can be pinned by unit tests
/// instead of discovered on a user's profile.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Last.fm's hard cap: "Up to 50 scrobbles may be sent in a single batch using
/// array notation" (`v1.5-w2w3-implementation-specs.md` A.1.4).
const int kLastFmMaxBatch = 50;

/// ListenBrainz accepts far more per request, but the specification recommends
/// the same 50 as Last.fm: one code path covers both backends and no test needs
/// a thousand-entry fixture (A.3.2).
const int kListenBrainzMaxBatch = 50;

/// Ceilings the ListenBrainz **server** enforces, kept here so a future batch
/// bump cannot silently cross one (A.3.2).
const int kListenBrainzMaxListensPerRequest = 1000;
const int kListenBrainzMaxPayloadBytes = 10240000;
const int kListenBrainzMaxListenBytes = 10240;

/// `LISTEN_MINIMUM_TS` ≈ 2002-10-01. ListenBrainz rejects anything older, so a
/// restored or clock-skewed library must be clamped rather than submitted.
const int kListenMinimumTs = 1033430400;

/// Minimum gap between two requests from the single scrobble pump.
///
/// 1.2 s satisfies ListenBrainz's "no more than one call per second per client"
/// **and** stays under Last.fm's ~5 req/s, so one serial pump serves both (A.6).
const Duration kScrobblePumpInterval = Duration(milliseconds: 1200);

/// Last.fm's own floor before a rate-limit error may be retried: "429/`29`
/// directly adopt the server hint or ≥30 s" (A.6).
const Duration kRateLimitFloor = Duration(seconds: 30);

/// Last.fm / Libre.fm request signature.
///
/// The rule (A.1.2, verbatim): *"MD5 signature of all request parameters
/// (excluding format and callback) sorted alphabetically by name, concatenated
/// as name+value pairs, with the shared secret appended."*
///
/// [params] must be **the exact map that will be sent**, minus
/// `format`/`callback`/`api_sig` (which are filtered here anyway). Two things
/// are easy to get wrong and are pinned by `test/scrobble_lastfm_test.dart`:
///
/// 1. a value must keep the very spelling that goes on the wire — an `int`
///    parameter must not be `8` when signing and `"08"` when sending;
/// 2. batch keys sort as plain strings, so `artist[0] < artist[10] < artist[2]`
///    (Dart's `String.compareTo` compares code units, which is exactly what the
///    server re-computes — do not "fix" the order).
String lastFmApiSig(Map<String, String> params, String sharedSecret) {
  final keys = params.keys
      .where((k) => k != 'format' && k != 'callback' && k != 'api_sig')
      .toList()
    ..sort();
  final buffer = StringBuffer();
  for (final key in keys) {
    buffer.write(key);
    buffer.write(params[key]);
  }
  buffer.write(sharedSecret);
  return md5.convert(utf8.encode(buffer.toString())).toString();
}

/// Whether a finished stretch of playback counts as one listen.
///
/// Authority (ListenBrainz Core API, quoted in A.5): *"Listens should be
/// submitted for tracks when the user has listened to half the track or 4
/// minutes of the track, whichever is lower."* Last.fm adds the floor: the
/// track must be **longer than 30 seconds**.
///
/// Both services also require a real play, so a resumed stretch is measured by
/// the time actually played, which is what the caller accumulates.
bool shouldScrobble({
  required Duration actualPlayed,
  required Duration trackDuration,
}) {
  if (trackDuration <= const Duration(seconds: 30)) return false;
  final half = Duration(milliseconds: trackDuration.inMilliseconds ~/ 2);
  final threshold = half < const Duration(minutes: 4)
      ? half
      : const Duration(minutes: 4);
  return actualPlayed >= threshold;
}

/// What to do with a Last.fm `<error code>` (A.6.1).
enum LastFmErrorDisposition {
  /// Credentials or app configuration are wrong: stop the pump for this
  /// service until the user acts.
  fatal,

  /// Worth another attempt (temporary outage, rate limit).
  retryable,

  /// This one listen will never be accepted: settle it and move on, so a single
  /// bad entry cannot wedge the queue.
  dropEntry,
}

/// Maps a Last.fm error code onto its disposition.
///
/// An **unknown** code is treated as retryable on purpose: dropping a listen on
/// a code this app has not seen would silently lose it, while retrying costs at
/// most five attempts before the outbox gives up on its own.
LastFmErrorDisposition lastFmErrorDisposition(int code) => switch (code) {
  // invalid session key / invalid api key / invalid method signature /
  // suspended api key — none of these get better by trying again.
  9 || 10 || 13 || 26 => LastFmErrorDisposition.fatal,
  // service temporarily unavailable / rate limit exceeded
  16 || 29 => LastFmErrorDisposition.retryable,
  // invalid parameters / operation failed — the entry itself is the problem
  6 || 8 => LastFmErrorDisposition.dropEntry,
  _ => LastFmErrorDisposition.retryable,
};

/// Short user-facing text for a Last.fm error code.
///
/// Hard-coded Chinese for now: W3-D moves user-visible strings into ARB, and
/// `lib/l10n/**` is outside this task's scope.
String lastFmErrorMessage(int code) => switch (code) {
  6 => '提交参数无效',
  8 => 'Last.fm 拒绝了这次提交',
  9 => 'Last.fm 会话已失效，请重新登录',
  10 => 'Last.fm API key 无效',
  13 => 'Last.fm 签名校验失败，请反馈',
  16 => 'Last.fm 服务暂时不可用',
  26 => '应用已被 Last.fm 暂时封禁',
  29 => '请求过于频繁，稍后自动重试',
  _ => 'Last.fm 返回错误码 $code',
};

/// Server-requested wait for [code], or null to use the outbox's own backoff.
Duration? lastFmRetryAfter(int code) =>
    code == 29 ? kRateLimitFloor : null;
