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
}
