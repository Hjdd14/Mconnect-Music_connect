/// The scrobble outbox's single writer and single sender.
///
/// Two responsibilities, deliberately in one class so there is exactly one
/// place that decides "what is deliverable now":
///
/// * [enqueue] — offline-first: a finished listen lands in `scrobble_queue`
///   immediately and the UI never waits for the network. Idempotence is the
///   DAO's contract (`ScrobbleQueueDao.enqueue` answers `false` for an
///   `(service, eventId)` it already holds), which is what makes a repeated
///   pause/resume flush produce one row and one submission — Last.fm has **no**
///   idempotency key of its own, so this is the only deduplication there is.
/// * [drainOnce] / [start] — a strictly serial pump: claim, submit, settle, and
///   never issue two requests closer than [pumpInterval] (ListenBrainz allows one
///   call per second per client; Last.fm about five).
library;

import '../../../core/database/app_database.dart';
import '../domain/scrobble_backend.dart';
import '../domain/scrobble_rules.dart';

/// What one [ScrobbleCoordinator.drainOnce] round did, for tests and the
/// settings page's "上次提交" line.
class ScrobbleDrainOutcome {
  const ScrobbleDrainOutcome({
    this.claimed = 0,
    this.settled = 0,
    this.retryable = 0,
    this.fatal = false,
    this.message,
  });

  final int claimed;
  final int settled;
  final int retryable;
  final bool fatal;
  final String? message;

  bool get didNothing => claimed == 0;

  @override
  String toString() =>
      'ScrobbleDrainOutcome(claimed: $claimed, settled: $settled, '
      'retryable: $retryable${fatal ? ', fatal' : ''})';
}

/// How long a claimed row may stay `sending` before another attempt may take it
/// over. Generous on purpose: a slow batch on mobile data is normal, while a
/// process killed mid-flight must not strand its rows forever.
const Duration kScrobbleLease = Duration(minutes: 2);

/// Pending rows older than this are dropped instead of retried forever.
///
/// The specification deliberately does **not** hard-code Last.fm's rejection
/// threshold for old timestamps (it could not be sourced), so the conservative
/// rule is local: keep a month of offline listening, drop what is older and say
/// so in the log.
const Duration kScrobblePendingRetention = Duration(days: 30);

Future<void> _defaultDelay(Duration duration) => Future<void>.delayed(duration);

class ScrobbleCoordinator {
  ScrobbleCoordinator({
    required this._queue,
    required this._backendProvider,
    this._pumpInterval = kScrobblePumpInterval,
    this._lease = kScrobbleLease,
    this._pendingRetention = kScrobblePendingRetention,
    DateTime Function()? now,
    this._delay = _defaultDelay,
  }) : _now = now ?? DateTime.now;

  final ScrobbleQueueDao _queue;
  final ScrobbleBackend? Function() _backendProvider;
  final Duration _pumpInterval;
  final Duration _lease;
  final Duration _pendingRetention;
  final DateTime Function() _now;
  final Future<void> Function(Duration duration) _delay;

  bool _running = false;

  /// Set when the service told us the credentials are dead (Last.fm 9/10/13/26,
  /// ListenBrainz 401). The pump stops; the settings page shows "需要重新登录".
  bool _needsReauth = false;

  String? _lastError;
  DateTime? _lastSuccessAt;

  bool get needsReauth => _needsReauth;
  bool get isRunning => _running;
  String? get lastError => _lastError;
  DateTime? get lastSuccessAt => _lastSuccessAt;

  /// Clears the re-auth latch after the settings page stored new credentials.
  void clearReauth() {
    _needsReauth = false;
    _lastError = null;
  }

  /// Records one finished listen. Returns whether a new row was created.
  Future<bool> enqueue({
    required int eventId,
    required String songKey,
    required String title,
    required String artist,
    required DateTime playedAt,
    String? album,
    Duration? duration,
  }) async {
    final backend = _backendProvider();
    if (backend == null) return false;
    final added = await _queue.enqueue(
      eventId: eventId,
      service: backend.id,
      songKey: songKey,
      title: title,
      artist: artist,
      album: album,
      // The outbox stores the play time in milliseconds; both services are sent
      // seconds, converted at the wire boundary so nothing is lost in between.
      playedAt: playedAt.millisecondsSinceEpoch,
      durationMs: duration?.inMilliseconds ?? 0,
      now: _now(),
    );
    return added;
  }

  /// Best-effort transient "now playing". Never queued, never retried.
  Future<void> nowPlaying({
    required String title,
    required String artist,
    String? album,
    Duration? duration,
  }) async {
    if (_needsReauth) return;
    final backend = _backendProvider();
    if (backend == null) return;
    try {
      await backend.nowPlaying(
        ScrobbleEntry(
          artist: artist,
          track: title,
          playedAt: _now(),
          album: album,
          durationSeconds: duration?.inSeconds,
        ),
      );
    } catch (_) {
      // Transient state: a failure here costs nothing and must not surface.
    }
  }

  /// One claim → submit → settle round. The unit of behaviour the tests drive.
  Future<ScrobbleDrainOutcome> drainOnce() async {
    if (_needsReauth) {
      return ScrobbleDrainOutcome(message: _lastError, fatal: true);
    }
    final backend = _backendProvider();
    if (backend == null) return const ScrobbleDrainOutcome();

    final claimed = <ScrobbleQueueRow>[];
    for (var i = 0; i < backend.maxBatchSize; i++) {
      final row = await _queue.claimNext(
        service: backend.id,
        lease: _lease,
        now: _now(),
      );
      if (row == null) break;
      claimed.add(row);
    }
    if (claimed.isEmpty) return const ScrobbleDrainOutcome();

    final entries = [for (final row in claimed) _entryOf(row)];
    final ScrobbleResult result;
    try {
      result = await backend.scrobble(entries);
    } catch (error) {
      // A backend that throws instead of classifying is treated as retryable:
      // the rows stay claimable and the pump backs off.
      final message = '提交失败：$error';
      for (final row in claimed) {
        await _queue.markFailed(
          row.id,
          error: message,
          attempts: row.attempts,
          at: _now(),
          baseDelay: kRateLimitFloor,
        );
      }
      _lastError = message;
      return ScrobbleDrainOutcome(
        claimed: claimed.length,
        retryable: claimed.length,
        message: message,
      );
    }

    _lastError = result.message;
    if (result.fatal) {
      _needsReauth = true;
      for (final row in claimed) {
        // Kept deliverable: after the user re-authenticates the same rows are
        // sent, so a fatal answer must not drop anyone's listening history.
        await _queue.markFailed(
          row.id,
          error: result.message ?? '凭据已失效',
          attempts: row.attempts,
          at: _now(),
          maxAttempts: 1 << 24,
        );
      }
      return ScrobbleDrainOutcome(
        claimed: claimed.length,
        fatal: true,
        message: result.message,
      );
    }

    if (result.retryable) {
      for (final row in claimed) {
        await _queue.markFailed(
          row.id,
          error: result.message ?? '稍后重试',
          attempts: row.attempts,
          at: _now(),
          // The server's own hint (Retry-After / X-RateLimit-Reset-In) becomes
          // the base of the DAO's exponential backoff, so a rate limit is never
          // retried sooner than the service asked for.
          baseDelay: result.retryAfter ?? kRateLimitFloor,
        );
      }
      return ScrobbleDrainOutcome(
        claimed: claimed.length,
        retryable: claimed.length,
        message: result.message,
      );
    }

    // Settled: `accepted` and `ignored` are both final answers (an ignored
    // scrobble will never be accepted, so re-sending it is pure noise).
    for (final row in claimed) {
      await _queue.markSent(row.id, at: _now());
    }
    _lastSuccessAt = _now();
    return ScrobbleDrainOutcome(
      claimed: claimed.length,
      settled: claimed.length,
      message: result.message,
    );
  }

  /// Drives [drainOnce] forever, with [pumpInterval] between requests.
  ///
  /// Awaits until [stop] is called, so callers `unawaited` it. Rows are claimed
  /// in play order and one batch is in flight at a time — that is what keeps the
  /// client under both services' rate limits.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      while (_running) {
        await drainOnce();
        if (!_running) break;
        await _delay(_pumpInterval);
      }
    } finally {
      _running = false;
    }
  }

  void stop() => _running = false;

  /// Drops pending rows whose play is older than [pendingRetention].
  ///
  /// Returns how many were dropped. Reuses the queue's own give-up transition
  /// rather than deleting: `dropped` rows are kept so a rescan cannot re-enqueue
  /// an event the app already decided about.
  Future<int> purgeStale({DateTime? now}) async {
    final at = now ?? _now();
    final cutoff = at.subtract(_pendingRetention).millisecondsSinceEpoch;
    final backend = _backendProvider();
    if (backend == null) return 0;
    var dropped = 0;
    for (final status in [ScrobbleStatus.pending, ScrobbleStatus.failed]) {
      final rows = await _queue.byStatus(backend.id, status);
      for (final row in rows) {
        if (row.playedAt >= cutoff) continue;
        await _queue.markFailed(
          row.id,
          error: '播放时间超过 ${_pendingRetention.inDays} 天，已放弃补交',
          attempts: 1,
          maxAttempts: 1,
          at: at,
        );
        dropped++;
      }
    }
    return dropped;
  }

  /// Rows waiting to be delivered, for the settings page.
  Future<int> pendingCount() async {
    final backend = _backendProvider();
    if (backend == null) return 0;
    final pending = await _queue.countByStatus(
      backend.id,
      ScrobbleStatus.pending,
    );
    final failed = await _queue.countByStatus(backend.id, ScrobbleStatus.failed);
    final sending = await _queue.countByStatus(
      backend.id,
      ScrobbleStatus.sending,
    );
    return pending + failed + sending;
  }

  ScrobbleEntry _entryOf(ScrobbleQueueRow row) => ScrobbleEntry(
    artist: row.artist,
    track: row.title,
    playedAt: DateTime.fromMillisecondsSinceEpoch(row.playedAt),
    album: row.album,
    durationSeconds: row.durationMs > 0 ? row.durationMs ~/ 1000 : null,
  );
}
