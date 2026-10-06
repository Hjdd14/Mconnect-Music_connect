import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/sleep_timer_provider.dart';

void main() {
  test('sleep timer pauses playback when the countdown expires', () async {
    var pauseCalls = 0;
    final notifier = SleepTimerNotifier(
      pausePlayback: () async {
        pauseCalls++;
      },
      initialDuration: const Duration(milliseconds: 20),
      tickInterval: const Duration(milliseconds: 10),
    );
    addTearDown(notifier.dispose);

    notifier.setEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 12));

    expect(notifier.state.enabled, isTrue);
    expect(pauseCalls, 0);

    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(pauseCalls, 1);
    expect(notifier.state.enabled, isFalse);
    expect(notifier.state.remaining, Duration.zero);
  });

  test('turning sleep timer off cancels the pending pause', () async {
    var pauseCalls = 0;
    final notifier = SleepTimerNotifier(
      pausePlayback: () async {
        pauseCalls++;
      },
      initialDuration: const Duration(milliseconds: 40),
      tickInterval: const Duration(milliseconds: 10),
    );
    addTearDown(notifier.dispose);

    notifier.setEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 12));
    notifier.setEnabled(false);
    await Future<void>.delayed(const Duration(milliseconds: 45));

    expect(pauseCalls, 0);
    expect(notifier.state.enabled, isFalse);
    expect(notifier.state.remaining, Duration.zero);
  });

  test('persists the sleep timer switch and remaining time', () async {
    final persisted = <({bool enabled, Duration remaining})>[];
    final notifier = SleepTimerNotifier(
      pausePlayback: () async {},
      persist: ({required bool enabled, required Duration remaining}) async {
        persisted.add((enabled: enabled, remaining: remaining));
      },
      initialDuration: const Duration(minutes: 30),
    );
    addTearDown(notifier.dispose);

    notifier.setEnabled(true);
    await pumpEventQueue();

    expect(notifier.state.enabled, isTrue);
    expect(persisted.last.enabled, isTrue);
    expect(persisted.last.remaining, const Duration(minutes: 30));

    notifier.setEnabled(false);
    await pumpEventQueue();

    expect(persisted.last.enabled, isFalse);
    expect(persisted.last.remaining, Duration.zero);
  });

  test('resumes a persisted countdown after a restart', () async {
    final notifier = SleepTimerNotifier(
      pausePlayback: () async {},
      initialDuration: const Duration(minutes: 30),
      initialEnabled: true,
      initialRemaining: const Duration(minutes: 25),
      tickInterval: const Duration(milliseconds: 10),
    );
    addTearDown(notifier.dispose);

    expect(notifier.state.enabled, isTrue);
    expect(notifier.state.remaining, const Duration(minutes: 25));

    await Future<void>.delayed(const Duration(milliseconds: 12));

    // 重启后倒计时继续走，而不是停在初始值。
    expect(notifier.state.remaining, lessThan(const Duration(minutes: 25)));
  });

  test('fades the audio out before pausing when the timer expires', () async {
    var pauseCalls = 0;
    var fadeOutCalls = 0;
    final notifier = SleepTimerNotifier(
      pausePlayback: () async {
        pauseCalls++;
      },
      fadeOutPause: () async {
        fadeOutCalls++;
      },
      initialDuration: const Duration(milliseconds: 20),
      tickInterval: const Duration(milliseconds: 10),
    );
    addTearDown(notifier.dispose);

    notifier.setEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 35));

    expect(fadeOutCalls, 1);
    expect(pauseCalls, 0);
    expect(notifier.state.enabled, isFalse);
  });
}
