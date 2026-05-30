import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

const _audioEffectsBoxName = 'settings';
const _audioEffectsKey = 'audio_effects_settings';

@immutable
class AudioEffectsSettings {
  final bool fadeEnabled;
  final Duration fadeDuration;
  final Duration sleepTimerDuration;

  const AudioEffectsSettings({
    this.fadeEnabled = false,
    this.fadeDuration = const Duration(milliseconds: 800),
    this.sleepTimerDuration = const Duration(minutes: 30),
  });

  AudioEffectsSettings copyWith({
    bool? fadeEnabled,
    Duration? fadeDuration,
    Duration? sleepTimerDuration,
  }) {
    return AudioEffectsSettings(
      fadeEnabled: fadeEnabled ?? this.fadeEnabled,
      fadeDuration: fadeDuration ?? this.fadeDuration,
      sleepTimerDuration: sleepTimerDuration ?? this.sleepTimerDuration,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fadeEnabled': fadeEnabled,
      'fadeDurationMs': fadeDuration.inMilliseconds,
      'sleepTimerDurationMinutes': sleepTimerDuration.inMinutes,
    };
  }

  static AudioEffectsSettings fromJson(dynamic value) {
    if (value is! Map) return const AudioEffectsSettings();
    return AudioEffectsSettings(
      fadeEnabled: value['fadeEnabled'] == true,
      fadeDuration: _durationFromMilliseconds(
        value['fadeDurationMs'],
        fallback: const Duration(milliseconds: 800),
        min: const Duration(milliseconds: 200),
        max: const Duration(seconds: 3),
      ),
      sleepTimerDuration: _durationFromMinutes(
        value['sleepTimerDurationMinutes'],
        fallback: const Duration(minutes: 30),
        min: const Duration(minutes: 5),
        max: const Duration(minutes: 120),
      ),
    );
  }

  static Duration _durationFromMilliseconds(
    dynamic value, {
    required Duration fallback,
    required Duration min,
    required Duration max,
  }) {
    final raw = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (raw == null) return fallback;
    return Duration(
      milliseconds: raw.clamp(min.inMilliseconds, max.inMilliseconds),
    );
  }

  static Duration _durationFromMinutes(
    dynamic value, {
    required Duration fallback,
    required Duration min,
    required Duration max,
  }) {
    final raw = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (raw == null) return fallback;
    return Duration(minutes: raw.clamp(min.inMinutes, max.inMinutes));
  }
}

final audioEffectsSettingsProvider =
    StateNotifierProvider<AudioEffectsSettingsNotifier, AudioEffectsSettings>((
      ref,
    ) {
      return AudioEffectsSettingsNotifier();
    });

class AudioEffectsSettingsNotifier extends StateNotifier<AudioEffectsSettings> {
  late final Future<void> ready = _load();

  AudioEffectsSettingsNotifier() : super(const AudioEffectsSettings());

  Future<void> _load() async {
    try {
      final box = await Hive.openBox(_audioEffectsBoxName);
      final raw = box.get(_audioEffectsKey);
      if (!mounted) return;
      state = AudioEffectsSettings.fromJson(raw);
    } catch (e, s) {
      debugPrint('AudioEffectsSettingsNotifier load failed: $e');
      debugPrint('$s');
    }
  }

  Future<void> setFadeEnabled(bool enabled) {
    return _save(state.copyWith(fadeEnabled: enabled));
  }

  Future<void> setFadeDuration(Duration duration) {
    final clamped = Duration(
      milliseconds: duration.inMilliseconds.clamp(200, 3000),
    );
    return _save(state.copyWith(fadeDuration: clamped));
  }

  Future<void> setSleepTimerDuration(Duration duration) {
    final clamped = Duration(minutes: duration.inMinutes.clamp(5, 120));
    return _save(state.copyWith(sleepTimerDuration: clamped));
  }

  Future<void> _save(AudioEffectsSettings settings) async {
    state = settings;
    try {
      final box = await Hive.openBox(_audioEffectsBoxName);
      await box.put(_audioEffectsKey, settings.toJson());
    } catch (e, s) {
      debugPrint('AudioEffectsSettingsNotifier save failed: $e');
      debugPrint('$s');
    }
  }
}
