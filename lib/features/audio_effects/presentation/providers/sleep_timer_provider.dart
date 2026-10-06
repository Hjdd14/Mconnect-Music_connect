import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../player/presentation/providers/player_provider.dart';
import 'audio_effects_provider.dart';

typedef PausePlayback = Future<void> Function();

/// Persists the sleep-timer runtime state; failures must never break the timer.
typedef PersistSleepTimer =
    Future<void> Function({required bool enabled, required Duration remaining});

/// How often the remaining time is written to storage while counting down.
///
/// Writing on every 1 Hz tick would be wasteful; a 10 s resolution is enough to
/// survive a restart without losing more than a few seconds of the countdown.
const Duration _persistInterval = Duration(seconds: 10);

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
        fadeOutPause: () =>
            ref.read(playerProvider.notifier).fadeOutAndPause(),
        persist: ({
          required bool enabled,
          required Duration remaining,
        }) => ref
            .read(audioEffectsSettingsProvider.notifier)
            .setSleepTimerState(enabled: enabled, remaining: remaining),
        initialDuration: settings.sleepTimerDuration,
        initialEnabled: settings.sleepTimerEnabled,
        initialRemaining: settings.sleepTimerRemaining,
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

  /// Preferred expiry action: fade the audio out before pausing.
  final PausePlayback? _fadeOutPause;
  final PersistSleepTimer? _persist;
  final Duration _tickInterval;
  Timer? _timer;
  Duration _lastPersistedRemaining = Duration.zero;

  SleepTimerNotifier({
    required this._pausePlayback,
    this._fadeOutPause,
    this._persist,
    Duration initialDuration = const Duration(minutes: 30),
    bool initialEnabled = false,
    Duration initialRemaining = Duration.zero,
    this._tickInterval = const Duration(seconds: 1),
  }) : super(
         SleepTimerState(
           enabled: initialEnabled,
           duration: initialDuration,
           remaining: initialEnabled
               ? (initialRemaining > Duration.zero
                     ? initialRemaining
                     : initialDuration)
               : Duration.zero,
         ),
       ) {
    _lastPersistedRemaining = state.remaining;
    if (state.enabled) {
      _startTimer();
    }
  }

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
      _persistState();
    }
  }

  void setEnabled(bool enabled) {
    if (!enabled) {
      _timer?.cancel();
      _timer = null;
      state = state.copyWith(enabled: false, remaining: Duration.zero);
      _persistState(force: true);
      return;
    }
    state = state.copyWith(enabled: true, remaining: state.duration);
    _startTimer();
    _persistState(force: true);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_tickInterval, (_) {
      final nextRemaining = state.remaining - _tickInterval;
      if (nextRemaining <= Duration.zero) {
        _timer?.cancel();
        _timer = null;
        state = state.copyWith(enabled: false, remaining: Duration.zero);
        _persistState(force: true);
        // 到点先淡出再暂停，避免音乐被硬切。
        final fadeOut = _fadeOutPause;
        unawaited(fadeOut != null ? fadeOut() : _pausePlayback());
      } else {
        state = state.copyWith(remaining: nextRemaining);
        _persistState();
      }
    });
  }

  void _persistState({bool force = false}) {
    final persist = _persist;
    if (persist == null) return;
    final remaining = state.remaining;
    if (!force &&
        (remaining - _lastPersistedRemaining).abs() < _persistInterval) {
      return;
    }
    _lastPersistedRemaining = remaining;
    unawaited(
      persist(enabled: state.enabled, remaining: remaining).catchError((
        Object error,
        StackTrace stack,
      ) {
        debugPrint('SleepTimerNotifier persist failed: $error');
      }),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
