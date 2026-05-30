import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../player/presentation/providers/player_provider.dart';
import 'audio_effects_provider.dart';

typedef PausePlayback = Future<void> Function();

@immutable
class SleepTimerState {
  final bool enabled;
  final Duration duration;
  final Duration remaining;

  const SleepTimerState({
    this.enabled = false,
    this.duration = const Duration(minutes: 30),
    this.remaining = Duration.zero,
  });

  SleepTimerState copyWith({
    bool? enabled,
    Duration? duration,
    Duration? remaining,
  }) {
    return SleepTimerState(
      enabled: enabled ?? this.enabled,
      duration: duration ?? this.duration,
      remaining: remaining ?? this.remaining,
    );
  }
}

final sleepTimerProvider =
    StateNotifierProvider<SleepTimerNotifier, SleepTimerState>((ref) {
      final settings = ref.read(audioEffectsSettingsProvider);
      final notifier = SleepTimerNotifier(
        pausePlayback: () => ref.read(playerProvider.notifier).pause(),
        initialDuration: settings.sleepTimerDuration,
      );

      ref.listen<AudioEffectsSettings>(audioEffectsSettingsProvider, (
        previous,
        next,
      ) {
        if (previous?.sleepTimerDuration != next.sleepTimerDuration) {
          notifier.setDuration(next.sleepTimerDuration);
        }
      });

      return notifier;
    });

class SleepTimerNotifier extends StateNotifier<SleepTimerState> {
  final PausePlayback _pausePlayback;
  final Duration _tickInterval;
  Timer? _timer;

  SleepTimerNotifier({
    required PausePlayback pausePlayback,
    Duration initialDuration = const Duration(minutes: 30),
    Duration tickInterval = const Duration(seconds: 1),
  }) : _pausePlayback = pausePlayback,
       _tickInterval = tickInterval,
       super(SleepTimerState(duration: initialDuration));

  void setDuration(Duration duration) {
    final clamped = duration.inMinutes < 5
        ? duration
        : Duration(minutes: duration.inMinutes.clamp(5, 120));
    state = state.copyWith(
      duration: clamped,
      remaining: state.enabled ? clamped : state.remaining,
    );
    if (state.enabled) {
      _startTimer();
    }
  }

  void setEnabled(bool enabled) {
    if (!enabled) {
      _timer?.cancel();
      _timer = null;
      state = state.copyWith(enabled: false, remaining: Duration.zero);
      return;
    }
    state = state.copyWith(enabled: true, remaining: state.duration);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_tickInterval, (_) {
      final nextRemaining = state.remaining - _tickInterval;
      if (nextRemaining <= Duration.zero) {
        _timer?.cancel();
        _timer = null;
        state = state.copyWith(enabled: false, remaining: Duration.zero);
        unawaited(_pausePlayback());
      } else {
        state = state.copyWith(remaining: nextRemaining);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
