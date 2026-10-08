import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/database/app_database.dart';
import 'package:mconnect/features/scrobble/data/scrobble_coordinator.dart';
import 'package:mconnect/features/scrobble/domain/scrobble_backend.dart';

/// A backend with no network: it records what it was asked to submit and answers
/// with a canned result.
class _FakeBackend implements ScrobbleBackend {
  _FakeBackend({
    this.result = const ScrobbleResult(accepted: 0),
    this.maxBatchSize = 50,
    this.throwOnNowPlaying = false,
  });

  ScrobbleResult result;

  @override
  final int maxBatchSize;

  final bool throwOnNowPlaying;

  int scrobbleCalls = 0;
  final List<List<ScrobbleEntry>> batches = [];
  final List<ScrobbleEntry> nowPlayingCalls = [];

  @override
  String get id => 'lastfm';

  @override
  String get displayName => 'Last.fm';

  @override
  bool get isConfigured => true;

  @override
  String? get lastError => null;

  @override
  Future<bool> validate() async => true;

  @override
  Future<void> nowPlaying(ScrobbleEntry entry) async {
    if (throwOnNowPlaying) throw StateError('no network');
    nowPlayingCalls.add(entry);
  }

  @override
  Future<ScrobbleResult> scrobble(List<ScrobbleEntry> entries) async {
    scrobbleCalls += 1;
    batches.add(entries);
    return result;
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// Builds a coordinator over the real DAO, with [backend] injectable because
  /// the point of these tests is the queue contract, not the transport.
  ScrobbleCoordinator coordinatorFor(
    ScrobbleBackend? backend, {
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  }) {
    return ScrobbleCoordinator(
      queue: db.scrobbleQueueDao,
      backendProvider: () => backend,
      now: now,
      delay: delay ?? ((_) async {}),
    );
  }

  Future<bool> enqueue(
    ScrobbleCoordinator coordinator, {
    required int eventId,
    required DateTime playedAt,
    String title = 'Karma Police',
    String artist = 'Radiohead',
  }) {
    return coordinator.enqueue(
      eventId: eventId,
      songKey: 'netease:$eventId',
      title: title,
      artist: artist,
      playedAt: playedAt,
      duration: const Duration(minutes: 4),
    );
  }

  group('ScrobbleCoordinator de-duplication', () {
    test('the same event enqueued twice is one row and one submission', () async {
      final backend = _FakeBackend(result: const ScrobbleResult(accepted: 1));
      final coordinator = coordinatorFor(backend);
      final playedAt = DateTime(2026, 5, 30, 10);

      final first = await enqueue(coordinator, eventId: 7, playedAt: playedAt);
      // The stats tracker flushes the same stretch more than once by design
      // (pause/resume), and Last.fm has **no** idempotency key of its own.
      final second = await enqueue(coordinator, eventId: 7, playedAt: playedAt);

      expect(first, isTrue);
      expect(second, isFalse, reason: 'enqueue 的 (service, eventId) 契约必须拒绝重复');
      expect(
        await db.scrobbleQueueDao.byStatus('lastfm', ScrobbleStatus.pending),
        hasLength(1),
      );

      final outcome = await coordinator.drainOnce();

      expect(backend.scrobbleCalls, 1);
      expect(backend.batches.single, hasLength(1));
      expect(outcome.settled, 1);

      // `sent` rows are kept — that is what stops a rescan from re-enqueuing an
      // event the app already delivered.
      expect(
        await db.scrobbleQueueDao.byStatus('lastfm', ScrobbleStatus.sent),
        hasLength(1),
      );
      expect(
        await enqueue(coordinator, eventId: 7, playedAt: playedAt),
        isFalse,
        reason: 'sent 行必须继续挡住同一个事件',
      );

      // A settled row is never claimed again.
      expect((await coordinator.drainOnce()).claimed, 0);
      expect(backend.scrobbleCalls, 1);
    });

    test('distinct events of one song are all delivered', () async {
      final backend = _FakeBackend(result: const ScrobbleResult(accepted: 2));
      final coordinator = coordinatorFor(backend);

      await enqueue(
        coordinator,
        eventId: 1,
        playedAt: DateTime(2026, 5, 30, 10),
      );
      await enqueue(
        coordinator,
        eventId: 2,
        playedAt: DateTime(2026, 5, 30, 11),
      );

      await coordinator.drainOnce();

      expect(backend.batches.single, hasLength(2));
      expect(
        await db.scrobbleQueueDao.countByStatus('lastfm', ScrobbleStatus.sent),
        2,
      );
    });
  });

  group('ScrobbleCoordinator pump', () {
    test('claims at most the batch size and drains the rest next round', () async {
      final backend = _FakeBackend(
        result: const ScrobbleResult(accepted: 3),
        maxBatchSize: 3,
      );
      final coordinator = coordinatorFor(backend);
      for (var i = 0; i < 5; i++) {
        await enqueue(
          coordinator,
          eventId: i,
          playedAt: DateTime(2026, 5, 30, 10).add(Duration(minutes: i)),
        );
      }

      final first = await coordinator.drainOnce();

      expect(first.claimed, 3, reason: '一次只在飞一批');
      expect(backend.batches.single, hasLength(3));
      // Oldest first, so a backlog is replayed in listening order.
      expect(
        backend.batches.single.map((entry) => entry.playedAt),
        [
          DateTime(2026, 5, 30, 10),
          DateTime(2026, 5, 30, 10, 1),
          DateTime(2026, 5, 30, 10, 2),
        ],
      );

      await coordinator.drainOnce();

      expect(backend.scrobbleCalls, 2);
      expect(
        await db.scrobbleQueueDao.countByStatus('lastfm', ScrobbleStatus.sent),
        5,
      );
    });

    test('a rate-limit answer delays the retry by the server hint', () async {
      final now = DateTime(2026, 5, 30, 12);
      final backend = _FakeBackend(
        result: const ScrobbleResult(
          accepted: 0,
          retryable: true,
          retryAfter: Duration(minutes: 5),
          message: '请求过于频繁',
        ),
      );
      final coordinator = coordinatorFor(backend, now: () => now);
      await enqueue(coordinator, eventId: 4, playedAt: now);

      final outcome = await coordinator.drainOnce();

      expect(outcome.retryable, 1);
      final rows = await db.scrobbleQueueDao.byStatus(
        'lastfm',
        ScrobbleStatus.failed,
      );
      expect(rows.single.attempts, 1);
      // The DAO's backoff is `baseDelay * 2^(attempts-1)`, and the base here is
      // the server's own hint — never sooner than the service asked for.
      expect(
        rows.single.nextAttemptAt,
        now.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
      );
    });

    test('a fatal answer latches re-auth and keeps the rows', () async {
      final backend = _FakeBackend(
        result: const ScrobbleResult(
          accepted: 0,
          fatal: true,
          message: 'Last.fm 会话已失效，请重新登录',
        ),
      );
      final coordinator = coordinatorFor(backend);
      await enqueue(
        coordinator,
        eventId: 9,
        playedAt: DateTime(2026, 5, 30, 10),
      );

      final outcome = await coordinator.drainOnce();

      expect(outcome.fatal, isTrue);
      expect(coordinator.needsReauth, isTrue);
      // Not dropped: once the user re-authenticates these rows must still go.
      expect(
        await db.scrobbleQueueDao.countByStatus(
          'lastfm',
          ScrobbleStatus.dropped,
        ),
        0,
      );
      expect(
        await db.scrobbleQueueDao.countByStatus('lastfm', ScrobbleStatus.failed),
        1,
      );

      // Latched: the pump makes no further requests until the user acts.
      expect((await coordinator.drainOnce()).claimed, 0);
      expect(backend.scrobbleCalls, 1);

      coordinator.clearReauth();
      expect(coordinator.needsReauth, isFalse);
    });

    test('a backend that throws is retried, not lost', () async {
      final backend = _ThrowingBackend();
      final coordinator = coordinatorFor(backend);
      await enqueue(
        coordinator,
        eventId: 11,
        playedAt: DateTime(2026, 5, 30, 10),
      );

      final outcome = await coordinator.drainOnce();

      expect(outcome.retryable, 1);
      expect(
        await db.scrobbleQueueDao.countByStatus('lastfm', ScrobbleStatus.failed),
        1,
      );
      expect(
        await db.scrobbleQueueDao.countByStatus('lastfm', ScrobbleStatus.sent),
        0,
      );
    });

    test('the pump stops when asked', () async {
      final backend = _FakeBackend();
      var delays = 0;
      late ScrobbleCoordinator coordinator;
      coordinator = coordinatorFor(
        backend,
        delay: (duration) async {
          delays += 1;
          if (delays >= 2) coordinator.stop();
        },
      );

      await coordinator.start();

      expect(delays, greaterThanOrEqualTo(2));
      expect(coordinator.isRunning, isFalse);
    });
  });

  group('ScrobbleCoordinator housekeeping', () {
    test('drops pending rows older than the retention window', () async {
      final now = DateTime(2026, 6, 30);
      final backend = _FakeBackend();
      final coordinator = coordinatorFor(backend, now: () => now);
      await enqueue(
        coordinator,
        eventId: 1,
        playedAt: now.subtract(const Duration(days: 40)),
      );
      await enqueue(
        coordinator,
        eventId: 2,
        playedAt: now.subtract(const Duration(days: 2)),
      );

      expect(await coordinator.purgeStale(), 1);
      expect(
        await db.scrobbleQueueDao.countByStatus(
          'lastfm',
          ScrobbleStatus.dropped,
        ),
        1,
      );
      expect(
        await db.scrobbleQueueDao.countByStatus('lastfm', ScrobbleStatus.pending),
        1,
      );
    });

    test('counts what is waiting for delivery', () async {
      final backend = _FakeBackend();
      final coordinator = coordinatorFor(backend);
      await enqueue(
        coordinator,
        eventId: 1,
        playedAt: DateTime(2026, 5, 30, 10),
      );
      await enqueue(
        coordinator,
        eventId: 2,
        playedAt: DateTime(2026, 5, 30, 11),
      );

      expect(await coordinator.pendingCount(), 2);
    });

    test('does nothing without a configured backend', () async {
      final coordinator = coordinatorFor(null);

      expect(
        await enqueue(
          coordinator,
          eventId: 1,
          playedAt: DateTime(2026, 5, 30, 10),
        ),
        isFalse,
      );
      expect((await coordinator.drainOnce()).claimed, 0);
      expect(await coordinator.pendingCount(), 0);
      expect(await coordinator.purgeStale(), 0);
      // Nothing to send, and nothing may throw.
      await coordinator.nowPlaying(title: 'T', artist: 'A');
    });

    test('a failing now-playing never propagates', () async {
      final backend = _FakeBackend(throwOnNowPlaying: true);
      final coordinator = coordinatorFor(backend);

      await coordinator.nowPlaying(
        title: 'Karma Police',
        artist: 'Radiohead',
        album: 'OK Computer',
        duration: const Duration(minutes: 4),
      );

      // Transient state: it is not queued and its failure is not the user's
      // problem, so it must not reach the caller or the outbox.
      expect(
        await db.scrobbleQueueDao.countByStatus('lastfm', ScrobbleStatus.pending),
        0,
      );
      expect(coordinator.needsReauth, isFalse);
    });

    test('now-playing is sent in play order metadata when configured', () async {
      final backend = _FakeBackend();
      final coordinator = coordinatorFor(backend);

      await coordinator.nowPlaying(
        title: 'Karma Police',
        artist: 'Radiohead',
        album: 'OK Computer',
        duration: const Duration(minutes: 4),
      );

      expect(backend.nowPlayingCalls.single.track, 'Karma Police');
      expect(backend.nowPlayingCalls.single.artist, 'Radiohead');
      expect(backend.nowPlayingCalls.single.album, 'OK Computer');
      expect(backend.nowPlayingCalls.single.durationSeconds, 240);
    });
  });
}

/// A backend whose `scrobble` throws, to pin the coordinator's fallback.
class _ThrowingBackend implements ScrobbleBackend {
  @override
  String get id => 'lastfm';

  @override
  String get displayName => 'Last.fm';

  @override
  bool get isConfigured => true;

  @override
  String? get lastError => null;

  @override
  int get maxBatchSize => 50;

  @override
  Future<bool> validate() async => true;

  @override
  Future<void> nowPlaying(ScrobbleEntry entry) async {}

  @override
  Future<ScrobbleResult> scrobble(List<ScrobbleEntry> entries) async {
    throw StateError('socket closed');
  }
}
