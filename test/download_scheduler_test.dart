import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/download/data/download_scheduler.dart';

/// The queue's own behaviour, with no notifier or manager involved.
void main() {
  late List<String> started;

  List<String> Function() starter() {
    started = <String>[];
    return () => started;
  }

  setUp(() {
    starter();
  });

  test('starts at most maxConcurrent downloads and keeps FIFO order',
      () async {
    final scheduler = DownloadScheduler(
      onStart: started.add,
      connectionCheck: () async => true,
    );
    addTearDown(scheduler.dispose);

    final outcomes = <DownloadEnqueueOutcome>[];
    for (final id in ['a', 'b', 'c', 'd', 'e']) {
      outcomes.add(await scheduler.enqueue(id));
    }

    expect(outcomes, [
      DownloadEnqueueOutcome.started,
      DownloadEnqueueOutcome.started,
      DownloadEnqueueOutcome.started,
      DownloadEnqueueOutcome.queued,
      DownloadEnqueueOutcome.queued,
    ]);
    expect(started, ['a', 'b', 'c']);
    expect(scheduler.activeCount, 3);
    expect(scheduler.pendingIds, ['d', 'e']);

    scheduler.complete('a');
    await pumpEventQueue();
    expect(started, ['a', 'b', 'c', 'd']);

    scheduler.complete('b');
    await pumpEventQueue();
    expect(started, ['a', 'b', 'c', 'd', 'e']);
  });

  test('enqueueing the same task twice is a no-op', () async {
    final scheduler = DownloadScheduler(
      onStart: started.add,
      connectionCheck: () async => true,
    );
    addTearDown(scheduler.dispose);

    expect(await scheduler.enqueue('a'), DownloadEnqueueOutcome.started);
    expect(await scheduler.enqueue('a'), DownloadEnqueueOutcome.duplicate);
    expect(started, ['a']);
  });

  test('the connection gate holds tasks and releases them on recheck',
      () async {
    var onWifi = false;
    final scheduler = DownloadScheduler(
      onStart: started.add,
      connectionCheck: () async => onWifi,
    );
    addTearDown(scheduler.dispose);

    expect(
      await scheduler.enqueue('a', requiresConnection: true),
      DownloadEnqueueOutcome.blockedNoConnection,
    );
    expect(started, isEmpty);
    expect(scheduler.heldIds, ['a']);

    // Still on mobile: nothing starts.
    expect(await scheduler.recheckHeld(), 0);
    expect(started, isEmpty);

    onWifi = true;
    expect(await scheduler.recheckHeld(), 1);
    expect(started, ['a']);
    expect(scheduler.heldIds, isEmpty);
  });

  test('a manual task bypasses the connection gate', () async {
    final scheduler = DownloadScheduler(
      onStart: started.add,
      connectionCheck: () async => false,
    );
    addTearDown(scheduler.dispose);

    expect(
      await scheduler.enqueue('manual'),
      DownloadEnqueueOutcome.started,
    );
    expect(started, ['manual']);
  });

  test('a held task can be started by hand', () async {
    final scheduler = DownloadScheduler(
      onStart: started.add,
      connectionCheck: () async => false,
    );
    addTearDown(scheduler.dispose);

    await scheduler.enqueue('a', requiresConnection: true);
    expect(
      await scheduler.enqueue('a'),
      DownloadEnqueueOutcome.started,
      reason: 'an explicit start drops the hold',
    );
    expect(started, ['a']);
  });

  test('pause stops new starts and resume restarts them', () async {
    final scheduler = DownloadScheduler(
      onStart: started.add,
      connectionCheck: () async => true,
    );
    addTearDown(scheduler.dispose);

    scheduler.pause();
    expect(
      await scheduler.enqueue('a'),
      DownloadEnqueueOutcome.blockedQueuePaused,
    );
    expect(started, isEmpty);

    await scheduler.resume();
    expect(started, ['a']);
    expect(scheduler.isPaused, isFalse);
  });

  test('remove drops a task from every stage without starting it', () async {
    final scheduler = DownloadScheduler(
      onStart: started.add,
      connectionCheck: () async => true,
    );
    addTearDown(scheduler.dispose);

    await scheduler.enqueue('a');
    await scheduler.enqueue('b');
    await scheduler.enqueue('c');
    await scheduler.enqueue('d');
    expect(scheduler.pendingIds, ['d']);

    scheduler.remove('d');
    expect(scheduler.pendingIds, isEmpty);
    scheduler.remove('a');
    expect(scheduler.isActive('a'), isFalse);

    // The freed slot is handed to nobody, but the queue is consistent.
    scheduler.complete('b');
    await pumpEventQueue();
    expect(started, ['a', 'b', 'c']);
  });
}
