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

  /// Sleep-timer runtime state, persisted so the countdown survives a restart
  /// (previously the switch and the remaining time were lost on every launch).
  final bool sleepTimerEnabled;
  final Duration sleepTimerRemaining;
  final bool equalizerEnabled;
  final EqualizerPreset equalizerPreset;
  final List<double> equalizerBandGains;

  const AudioEffectsSettings({
    this.fadeEnabled = false,
    this.fadeDuration = const Duration(milliseconds: 800),
    this.sleepTimerDuration = const Duration(minutes: 30),
    this.sleepTimerEnabled = false,
    this.sleepTimerRemaining = Duration.zero,
    this.equalizerEnabled = false,
    this.equalizerPreset = EqualizerPreset.flat,
    this.equalizerBandGains = const [0, 0, 0, 0, 0],
  });

  AudioEffectsSettings copyWith({
    bool? fadeEnabled,
    Duration? fadeDuration,
    Duration? sleepTimerDuration,
    bool? sleepTimerEnabled,
    Duration? sleepTimerRemaining,
    bool? equalizerEnabled,
    EqualizerPreset? equalizerPreset,
    List<double>? equalizerBandGains,
  }) {
    return AudioEffectsSettings(
      fadeEnabled: fadeEnabled ?? this.fadeEnabled,
      fadeDuration: fadeDuration ?? this.fadeDuration,
      sleepTimerDuration: sleepTimerDuration ?? this.sleepTimerDuration,
      sleepTimerEnabled: sleepTimerEnabled ?? this.sleepTimerEnabled,
      sleepTimerRemaining: sleepTimerRemaining ?? this.sleepTimerRemaining,
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
      'sleepTimerEnabled': sleepTimerEnabled,
      'sleepTimerRemainingSeconds': sleepTimerRemaining.inSeconds,
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
      sleepTimerEnabled: value['sleepTimerEnabled'] == true,
      sleepTimerRemaining: _durationFromSeconds(
        value['sleepTimerRemainingSeconds'],
        fallback: Duration.zero,
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

  static Duration _durationFromSeconds(
    dynamic value, {
    required Duration fallback,
    required Duration max,
  }) {
    final raw = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (raw == null) return fallback;
    final clamped = raw.clamp(0, max.inSeconds);
    return Duration(seconds: clamped);
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

/// 读/写音频增强设置的存储 seam（形状与理由同 `AutoSourceSwitchStore`）。
///
/// 探针实测：点击这一页的开关（例如「淡入淡出」）→ `_save()` 里的
/// `await Hive.openBox(...).put(...)` 被 UI 回调 fire-and-forget，真实 I/O 的
/// continuation 留在 FakeAsync 队列里 ⇒ 文件级 `tearDown` 的 `Hive.close()` 一直等它
/// （`PROBE D: hiveClose=closed-TIMEOUT(3s)`，且与具体开关无关）。
///
/// 生产仍写 Hive；widget 测试 override [audioEffectsSettingsStoreProvider] 成
/// [MemoryAudioEffectsSettingsStore]；"真的落盘了"由
/// `test/settings_persistence_test.dart` 的持久化单测保证（否则"点击只改内存"
/// 会变成新的假绿）。
///
/// 注意构造函数的 [AudioEffectsSettingsNotifier] 仍然**允许零参数**：
/// `test/audio_enhancement_settings_test.dart` 直接 `AudioEffectsSettingsNotifier()`，
/// 那种 plain `test()` 里没有 FakeAsync，真实 Hive I/O 正常完成，所以默认走 Hive 是对的。
abstract class AudioEffectsSettingsStore {
  /// `null` = 没存过 ⇒ 用 [AudioEffectsSettings] 的默认值。
  Object? read();

  Future<void> write(Map<String, dynamic> json);
}

class HiveAudioEffectsSettingsStore implements AudioEffectsSettingsStore {
  const HiveAudioEffectsSettingsStore();

  @override
  Object? read() {
    try {
      return Hive.box(_audioEffectsBoxName).get(_audioEffectsKey);
    } catch (e, s) {
      debugPrint('AudioEffectsSettingsStore read failed: $e');
      debugPrint('$s');
      return null;
    }
  }

  @override
  Future<void> write(Map<String, dynamic> json) async {
    try {
      final box = await Hive.openBox(_audioEffectsBoxName);
      await box.put(_audioEffectsKey, json);
    } catch (e, s) {
      debugPrint('AudioEffectsSettingsStore write failed: $e');
      debugPrint('$s');
    }
  }
}

/// 测试实现：不碰 Hive；`writes` 记录每一次落盘请求。
class MemoryAudioEffectsSettingsStore implements AudioEffectsSettingsStore {
  MemoryAudioEffectsSettingsStore([this._value]);

  Object? _value;

  /// 当前"已存"的 JSON（null = 从未写过）。
  Object? get value => _value;

  /// 依次收到的写入（用来断言"设置确实要求落盘了"）。
  final List<Map<String, dynamic>> writes = <Map<String, dynamic>>[];

  @override
  Object? read() => _value;

  @override
  Future<void> write(Map<String, dynamic> json) async {
    _value = json;
    writes.add(json);
  }
}

/// 注入点：生产用 Hive；widget 测试 override 成内存实现。
final audioEffectsSettingsStoreProvider = Provider<AudioEffectsSettingsStore>(
  (ref) => const HiveAudioEffectsSettingsStore(),
);

final audioEffectsSettingsProvider =
    StateNotifierProvider<AudioEffectsSettingsNotifier, AudioEffectsSettings>((
      ref,
    ) {
      return AudioEffectsSettingsNotifier(
        ref.read(audioEffectsSettingsStoreProvider),
      );
    });

class AudioEffectsSettingsNotifier extends StateNotifier<AudioEffectsSettings> {
  /// 历史遗留（无副作用、永远已完成）：保留是为了不扩大这次改动的面。
  Future<void> ready = Future.value();

  AudioEffectsSettingsNotifier([AudioEffectsSettingsStore? store])
    : _store = store ?? const HiveAudioEffectsSettingsStore(),
      super(const AudioEffectsSettings()) {
    _load();
  }

  final AudioEffectsSettingsStore _store;

  void _load() {
    final raw = _store.read();
    if (!mounted) return;
    state = AudioEffectsSettings.fromJson(raw);
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

  /// Persists the sleep-timer runtime state (switch + remaining time).
  Future<void> setSleepTimerState({
    required bool enabled,
    required Duration remaining,
  }) {
    final clamped = Duration(
      seconds: remaining.inSeconds.clamp(0, const Duration(minutes: 120).inSeconds),
    );
    return _save(
      state.copyWith(sleepTimerEnabled: enabled, sleepTimerRemaining: clamped),
    );
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
    // 存储自己吞掉异常（见 AudioEffectsSettingsStore 的实现）：一次落盘失败
    // 不能让 UI 抛错，这是本文件既有的降级约定。
    await _store.write(settings.toJson());
  }
}
