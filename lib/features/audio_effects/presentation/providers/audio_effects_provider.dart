import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

const _audioEffectsBoxName = 'settings';
const _audioEffectsKey = 'audio_effects_settings';

enum EqualizerPreset { flat, bassBoost, vocal, rock, custom }

extension EqualizerPresetLabels on EqualizerPreset {
  String get displayName {
    switch (this) {
      case EqualizerPreset.flat:
        return '平直';
      case EqualizerPreset.bassBoost:
        return '低音增强';
      case EqualizerPreset.vocal:
        return '人声';
      case EqualizerPreset.rock:
        return '摇滚';
      case EqualizerPreset.custom:
        return '自定义';
    }
  }

  List<double> get bandGains {
    switch (this) {
      case EqualizerPreset.flat:
        return const [0, 0, 0, 0, 0];
      case EqualizerPreset.bassBoost:
        return const [6, 4, 1, 0, 0];
      case EqualizerPreset.vocal:
        return const [-2, 0, 5, 3, 1];
      case EqualizerPreset.rock:
        return const [4, 2, 0, 3, 5];
      case EqualizerPreset.custom:
        return const [0, 0, 0, 0, 0];
    }
  }
}

@immutable
class EqualizerBandGain {
  final int bandIndex;
  final double gain;

  const EqualizerBandGain(this.bandIndex, this.gain);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EqualizerBandGain &&
          runtimeType == other.runtimeType &&
          bandIndex == other.bandIndex &&
          gain == other.gain;

  @override
  int get hashCode => Object.hash(bandIndex, gain);

  @override
  String toString() => 'EqualizerBandGain($bandIndex, $gain)';
}

@immutable
class AudioEffectsSettings {
  final bool fadeEnabled;
  final Duration fadeDuration;
  final Duration sleepTimerDuration;
  final bool equalizerEnabled;
  final EqualizerPreset equalizerPreset;
  final List<double> equalizerBandGains;

  const AudioEffectsSettings({
    this.fadeEnabled = false,
    this.fadeDuration = const Duration(milliseconds: 800),
    this.sleepTimerDuration = const Duration(minutes: 30),
    this.equalizerEnabled = false,
    this.equalizerPreset = EqualizerPreset.flat,
    this.equalizerBandGains = const [0, 0, 0, 0, 0],
  });

  AudioEffectsSettings copyWith({
    bool? fadeEnabled,
    Duration? fadeDuration,
    Duration? sleepTimerDuration,
    bool? equalizerEnabled,
    EqualizerPreset? equalizerPreset,
    List<double>? equalizerBandGains,
  }) {
    return AudioEffectsSettings(
      fadeEnabled: fadeEnabled ?? this.fadeEnabled,
      fadeDuration: fadeDuration ?? this.fadeDuration,
      sleepTimerDuration: sleepTimerDuration ?? this.sleepTimerDuration,
      equalizerEnabled: equalizerEnabled ?? this.equalizerEnabled,
      equalizerPreset: equalizerPreset ?? this.equalizerPreset,
      equalizerBandGains: equalizerBandGains ?? this.equalizerBandGains,
    );
  }

  List<double> get effectiveEqualizerBandGains {
    return equalizerPreset == EqualizerPreset.custom
        ? equalizerBandGains
        : equalizerPreset.bandGains;
  }

  Map<String, dynamic> toJson() {
    return {
      'fadeEnabled': fadeEnabled,
      'fadeDurationMs': fadeDuration.inMilliseconds,
      'sleepTimerDurationMinutes': sleepTimerDuration.inMinutes,
      'equalizerEnabled': equalizerEnabled,
      'equalizerPreset': equalizerPreset.name,
      'equalizerBandGains': equalizerBandGains,
    };
  }

  static AudioEffectsSettings fromJson(dynamic value) {
    if (value is! Map) return const AudioEffectsSettings();
    final presetName = value['equalizerPreset']?.toString();
    final preset = EqualizerPreset.values.firstWhere(
      (item) => item.name == presetName,
      orElse: () => EqualizerPreset.flat,
    );
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
      equalizerEnabled: value['equalizerEnabled'] == true,
      equalizerPreset: preset,
      equalizerBandGains: _equalizerBandGainsFromJson(
        value['equalizerBandGains'],
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

  static List<double> _equalizerBandGainsFromJson(dynamic value) {
    if (value is! List) return const [0, 0, 0, 0, 0];
    final gains = value
        .map((item) => double.tryParse(item.toString()) ?? 0)
        .map(_clampGain)
        .take(5)
        .toList();
    while (gains.length < 5) {
      gains.add(0);
    }
    return gains;
  }

  static double _clampGain(num value) => value.clamp(-12, 12).toDouble();
}

final audioEffectsSettingsProvider =
    StateNotifierProvider<AudioEffectsSettingsNotifier, AudioEffectsSettings>((
      ref,
    ) {
      return AudioEffectsSettingsNotifier();
    });

class AudioEffectsSettingsNotifier extends StateNotifier<AudioEffectsSettings> {
  Future<void> ready = Future.value();

  AudioEffectsSettingsNotifier() : super(const AudioEffectsSettings()) {
    _load();
  }

  void _load() {
    try {
      final box = Hive.box(_audioEffectsBoxName);
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

  Future<void> setEqualizerEnabled(bool enabled) {
    return _save(state.copyWith(equalizerEnabled: enabled));
  }

  Future<void> setEqualizerPreset(EqualizerPreset preset) {
    return _save(
      state.copyWith(
        equalizerPreset: preset,
        equalizerBandGains: preset == EqualizerPreset.custom
            ? state.equalizerBandGains
            : preset.bandGains,
      ),
    );
  }

  Future<void> setEqualizerBandGain(int index, double gain) {
    if (index < 0 || index >= state.equalizerBandGains.length) {
      return Future.value();
    }
    final gains = List<double>.from(state.equalizerBandGains);
    gains[index] = AudioEffectsSettings._clampGain(gain);
    return _save(
      state.copyWith(
        equalizerPreset: EqualizerPreset.custom,
        equalizerBandGains: gains,
      ),
    );
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
