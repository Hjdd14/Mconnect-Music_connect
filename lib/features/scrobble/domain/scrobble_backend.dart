/// The contract every scrobbling transport implements.
///
/// Two transports cover four services (`v1.5-w2w3-implementation-specs.md` A.4):
///
/// * [LastFmCompatibleBackend] — `api_key` + `api_sig` + `sk`, i.e. Last.fm,
///   Libre.fm and self-hosted GNU FM. It is the only family whose signature the
///   server actually verifies (Last.fm error code 13);
/// * [ListenBrainzNativeBackend] — `Authorization: Token` + JSON, i.e.
///   ListenBrainz and Maloja.
///
/// The ListenBrainz *Last.fm-compatible proxy* (`proxy.listenbrainz.org`) is
/// deliberately not a path here: it requires an `api_key` registered with
/// ListenBrainz plus a token/session exchange, while the native API needs the
/// user to paste one token. Its only value is pointing an **existing** Last.fm
/// client at ListenBrainz.
library;

/// One track the user listened to, ready to be submitted.
///
/// Deliberately free of queue and account state: the outbox row carries the
/// service, the event id and the attempts, so one entry can be handed to any
/// backend unchanged.
class ScrobbleEntry {
  const ScrobbleEntry({
    required this.artist,
    required this.track,
    required this.playedAt,
    this.album,
    this.albumArtist,
    this.trackNumber,
    this.durationSeconds,
    this.mbid,
    this.originUrl,
  });

  final String artist;
  final String track;

  /// When playback **started** (both services want the start, not the end).
  final DateTime playedAt;

  final String? album;
  final String? albumArtist;
  final int? trackNumber;
  final int? durationSeconds;
  final String? mbid;

  /// Deep link back to the platform page, for ListenBrainz's `origin_url`.
  final String? originUrl;

  /// Playback start as Unix **seconds** — the wire shape of both services.
  ///
  /// Truncating (not rounding) is what `~/` does; Last.fm recomputes its
  /// signature over the same string it receives, so the two must not drift.
  int get playedAtSeconds => playedAt.millisecondsSinceEpoch ~/ 1000;

  @override
  String toString() =>
      'ScrobbleEntry($artist — $track @ ${playedAt.toIso8601String()})';
}

/// How a submission ended, in the only three shapes the outbox needs to know.
///
/// The distinction is carried by flags rather than by an enum because a batch
/// can be *partly* ignored: Last.fm answers HTTP 200 with
/// `{"scrobbles":{"@attr":{"accepted":1,"ignored":49}}}`, and `ignored` entries
/// are permanently rejected, not retryable.
class ScrobbleResult {
  const ScrobbleResult({
    required this.accepted,
    this.ignored = 0,
    this.retryable = false,
    this.fatal = false,
    this.message,
    this.retryAfter,
  });

  /// Entries the service stored.
  final int accepted;

  /// Entries the service refused for a reason that will not change (bad
  /// parameters, unknown track). Settled, never retried.
  final int ignored;

  /// The same request may succeed later (network, 5xx, rate limit).
  final bool retryable;

  /// The credentials or the app configuration are wrong; the caller must stop
  /// draining this backend until the user fixes it (`A.6.2` item 6).
  final bool fatal;

  /// Server- or library-supplied text, safe to show/log (never a credential:
  /// the redactor is a second line of defence, not the first).
  final String? message;

  /// How long to wait before the next attempt, when the server said so
  /// (`Retry-After`, ListenBrainz's `X-RateLimit-Reset-In`, Last.fm code 29).
  final Duration? retryAfter;

  int get total => accepted + ignored;

  ScrobbleResult merged(ScrobbleResult other) => ScrobbleResult(
    accepted: accepted + other.accepted,
    ignored: ignored + other.ignored,
    retryable: retryable || other.retryable,
    fatal: fatal || other.fatal,
    message: other.message ?? message,
    retryAfter: other.retryAfter ?? retryAfter,
  );

  static ScrobbleResult ok({required int accepted, int ignored = 0}) =>
      ScrobbleResult(accepted: accepted, ignored: ignored);

  static ScrobbleResult retry(String message, {Duration? retryAfter}) =>
      ScrobbleResult(
        accepted: 0,
        retryable: true,
        message: message,
        retryAfter: retryAfter,
      );

  static ScrobbleResult permanent(String message, {int ignored = 0}) =>
      ScrobbleResult(accepted: 0, ignored: ignored, message: message);

  static ScrobbleResult failed(String message) =>
      ScrobbleResult(accepted: 0, fatal: true, message: message);

  @override
  String toString() =>
      'ScrobbleResult(accepted: $accepted, ignored: $ignored'
      '${retryable ? ', retryable' : ''}${fatal ? ', fatal' : ''}'
      '${message == null ? '' : ', $message'})';
}

/// One scrobbling service.
abstract class ScrobbleBackend {
  /// Stable id persisted in `scrobble_queue.service`:
  /// `lastfm` | `librefm` | `gnufm` | `listenbrainz` | `maloja`.
  String get id;

  /// Human label for the settings page (Chinese; W3-D moves strings to ARB).
  String get displayName;

  /// False when the user has not supplied the credentials this backend needs.
  bool get isConfigured;

  /// Cheap credential probe for the settings page's 「测试连接」.
  ///
  /// Must not submit a listen and must not throw for a plain "invalid token":
  /// it answers `false` and says why in [lastError].
  Future<bool> validate();

  /// Last message from [validate] / a submission, for display.
  String? get lastError;

  /// Transient "now playing" state.
  ///
  /// Never retried and never queued: it is not a listen (`A.5`), so a failure
  /// costs nothing and retrying it would only pollute the outbox.
  Future<void> nowPlaying(ScrobbleEntry entry);

  /// Submits [entries] (already split to the backend's batch limit) as
  /// **listens**, preserving each entry's original play time.
  Future<ScrobbleResult> scrobble(List<ScrobbleEntry> entries);

  /// Largest batch [scrobble] accepts in one request.
  int get maxBatchSize;
}
