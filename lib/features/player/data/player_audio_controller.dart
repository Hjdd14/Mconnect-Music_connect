import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/platform/platform_utils.dart';

class AudioPlaybackState {
  final bool playing;
  final ProcessingState processingState;

  const AudioPlaybackState({
    required this.playing,
    required this.processingState,
  });
}

abstract class PlayerAudioController {
  bool get playing;
  Duration get position;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<AudioPlaybackState> get playerStateStream;

  Future<void> stop();
  Future<void> setUrl(String url);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> bandGains,
  });
  Future<void> dispose();
}

class JustAudioController implements PlayerAudioController {
  static const double _maxAndroidLoudnessCompensationDb = 6.0;

  final AudioPlayer _player;
  final AndroidEqualizer? _equalizer;
  final AndroidLoudnessEnhancer? _loudnessEnhancer;
  AndroidEqualizerParameters? _equalizerParameters;
  int _equalizerApplyGeneration = 0;

  JustAudioController([
    AudioPlayer? player,
    AndroidEqualizer? equalizer,
    AndroidLoudnessEnhancer? loudnessEnhancer,
  ]) : this._(
         player,
         equalizer ?? createAndroidEqualizerForPlatform(),
         loudnessEnhancer ?? createAndroidLoudnessEnhancerForPlatform(),
       );

  JustAudioController._(
    AudioPlayer? player,
    AndroidEqualizer? equalizer,
    AndroidLoudnessEnhancer? loudnessEnhancer,
  ) : _equalizer = equalizer,
      _loudnessEnhancer = loudnessEnhancer,
      _player =
          player ??
          AudioPlayer(
            audioPipeline: _androidAudioPipeline(
              equalizer: equalizer,
              loudnessEnhancer: loudnessEnhancer,
            ),
          );

  AudioPlayer get player => _player;

  @visibleForTesting
  static ({
    bool equalizerEnabled,
    List<double> bandGains,
    bool loudnessEnabled,
    double loudnessGain,
  })
  androidEqualizerPlanForTest({
    required bool enabled,
    required List<double> bandGains,
    required int bandCount,
    required double minDecibels,
    required double maxDecibels,
  }) {
    return _androidEqualizerPlan(
      enabled: enabled,
      bandGains: bandGains,
      bandCount: bandCount,
      minDecibels: minDecibels,
      maxDecibels: maxDecibels,
    );
  }

  @visibleForTesting
  static Future<void> applyAndroidEqualizerPlanForTest({
    required bool enabled,
    required List<double> bandGains,
    required int bandCount,
    required double minDecibels,
    required double maxDecibels,
    required Future<void> Function(bool enabled) setEnabled,
    required Future<void> Function(int index, double gain) setBandGain,
    required Future<void> Function(bool enabled) setLoudnessEnabled,
    required Future<void> Function(double gain) setLoudnessGain,
    bool Function()? shouldContinue,
  }) {
    return _applyAndroidEqualizerPlan(
      enabled: enabled,
      bandGains: bandGains,
      bandCount: bandCount,
      minDecibels: minDecibels,
      maxDecibels: maxDecibels,
      setEnabled: setEnabled,
      setBandGain: setBandGain,
      setLoudnessEnabled: setLoudnessEnabled,
      setLoudnessGain: setLoudnessGain,
      shouldContinue: shouldContinue,
    );
  }

  @override
  bool get playing => _player.playing;

  @override
  Duration get position => _player.position;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<AudioPlaybackState> get playerStateStream =>
      _player.playerStateStream.map(
        (state) => AudioPlaybackState(
          playing: state.playing,
          processingState: state.processingState,
        ),
      );

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> setUrl(String url) => _player.setUrl(url).then((_) {});

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> bandGains,
  }) async {
    final equalizer = _equalizer;
    final loudnessEnhancer = _loudnessEnhancer;
    final generation = ++_equalizerApplyGeneration;
    if (equalizer == null) {
      await _disableAndroidLoudness(
        setLoudnessEnabled: loudnessEnhancer?.setEnabled,
        setLoudnessGain: loudnessEnhancer?.setTargetGain,
        shouldContinue: () => generation == _equalizerApplyGeneration,
      );
      return;
    }
    if (!enabled || _isFlatEqualizerCurve(bandGains)) {
      await _disableAndroidLoudness(
        setLoudnessEnabled: loudnessEnhancer?.setEnabled,
        setLoudnessGain: loudnessEnhancer?.setTargetGain,
        shouldContinue: () => generation == _equalizerApplyGeneration,
      );
      if (generation != _equalizerApplyGeneration) return;
      await equalizer.setEnabled(false);
      return;
    }

    final parameters = _equalizerParameters;
    if (parameters != null) {
      await _applyAndroidEqualizerParameters(
        equalizer: equalizer,
        loudnessEnhancer: loudnessEnhancer,
        parameters: parameters,
        enabled: enabled,
        bandGains: bandGains,
        generation: generation,
      );
      return;
    }

    await _disableAndroidLoudness(
      setLoudnessEnabled: loudnessEnhancer?.setEnabled,
      setLoudnessGain: loudnessEnhancer?.setTargetGain,
      shouldContinue: () => generation == _equalizerApplyGeneration,
    );
    if (generation != _equalizerApplyGeneration) return;
    unawaited(
      _applyAndroidEqualizerWhenParametersReady(
        equalizer: equalizer,
        loudnessEnhancer: loudnessEnhancer,
        enabled: enabled,
        bandGains: List<double>.of(bandGains),
        generation: generation,
      ),
    );
  }

  Future<void> _applyAndroidEqualizerWhenParametersReady({
    required AndroidEqualizer equalizer,
    required AndroidLoudnessEnhancer? loudnessEnhancer,
    required bool enabled,
    required List<double> bandGains,
    required int generation,
  }) async {
    try {
      final parameters = await equalizer.parameters;
      _equalizerParameters = parameters;
      await _applyAndroidEqualizerParameters(
        equalizer: equalizer,
        loudnessEnhancer: loudnessEnhancer,
        parameters: parameters,
        enabled: enabled,
        bandGains: bandGains,
        generation: generation,
      );
    } catch (error) {
      debugPrint('JustAudioController Android equalizer failed: $error');
    }
  }

  Future<void> _applyAndroidEqualizerParameters({
    required AndroidEqualizer equalizer,
    required AndroidLoudnessEnhancer? loudnessEnhancer,
    required AndroidEqualizerParameters parameters,
    required bool enabled,
    required List<double> bandGains,
    required int generation,
  }) {
    return _applyAndroidEqualizerPlan(
      enabled: enabled,
      bandGains: bandGains,
      bandCount: parameters.bands.length,
      minDecibels: parameters.minDecibels,
      maxDecibels: parameters.maxDecibels,
      shouldContinue: () => generation == _equalizerApplyGeneration,
      setEnabled: equalizer.setEnabled,
      setBandGain: (index, gain) => parameters.bands[index].setGain(gain),
      setLoudnessEnabled: loudnessEnhancer?.setEnabled,
      setLoudnessGain: loudnessEnhancer?.setTargetGain,
    );
  }

  @override
  Future<void> dispose() => _player.dispose();
}

@visibleForTesting
AndroidEqualizer? createAndroidEqualizerForPlatform() {
  return PlatformUtils.isAndroid ? AndroidEqualizer() : null;
}

@visibleForTesting
AndroidLoudnessEnhancer? createAndroidLoudnessEnhancerForPlatform() {
  return PlatformUtils.isAndroid ? AndroidLoudnessEnhancer() : null;
}

AudioPipeline? _androidAudioPipeline({
  required AndroidEqualizer? equalizer,
  required AndroidLoudnessEnhancer? loudnessEnhancer,
}) {
  final effects = <AndroidAudioEffect>[?loudnessEnhancer, ?equalizer];
  if (effects.isEmpty) return null;
  return AudioPipeline(androidAudioEffects: effects);
}

bool _isFlatEqualizerCurve(List<double> bandGains) {
  return bandGains.every((gain) => gain.abs() < 0.01);
}

Future<void> _applyAndroidEqualizerPlan({
  required bool enabled,
  required List<double> bandGains,
  required int bandCount,
  required double minDecibels,
  required double maxDecibels,
  required Future<void> Function(bool enabled) setEnabled,
  required Future<void> Function(int index, double gain) setBandGain,
  Future<void> Function(bool enabled)? setLoudnessEnabled,
  Future<void> Function(double gain)? setLoudnessGain,
  bool Function()? shouldContinue,
}) async {
  bool isCurrent() => shouldContinue?.call() ?? true;

  final plan = _androidEqualizerPlan(
    enabled: enabled,
    bandGains: bandGains,
    bandCount: bandCount,
    minDecibels: minDecibels,
    maxDecibels: maxDecibels,
  );
  if (!isCurrent()) return;
  await _disableAndroidLoudness(
    setLoudnessEnabled: setLoudnessEnabled,
    setLoudnessGain: setLoudnessGain,
    shouldContinue: isCurrent,
  );
  if (!isCurrent()) return;
  if (!plan.equalizerEnabled) {
    await setEnabled(false);
    return;
  }

  for (var i = 0; i < plan.bandGains.length; i++) {
    if (!isCurrent()) return;
    await setBandGain(i, plan.bandGains[i]);
  }
  if (!isCurrent()) return;
  await setEnabled(true);
  if (!isCurrent() || !plan.loudnessEnabled) return;
  await _enableAndroidLoudness(
    gain: plan.loudnessGain,
    setLoudnessEnabled: setLoudnessEnabled,
    setLoudnessGain: setLoudnessGain,
    shouldContinue: isCurrent,
  );
}

({
  bool equalizerEnabled,
  List<double> bandGains,
  bool loudnessEnabled,
  double loudnessGain,
})
_androidEqualizerPlan({
  required bool enabled,
  required List<double> bandGains,
  required int bandCount,
  required double minDecibels,
  required double maxDecibels,
}) {
  final count = max(0, bandCount);
  final flatGains = List<double>.filled(count, 0);
  if (!enabled || count == 0 || minDecibels >= 0) {
    return (
      equalizerEnabled: false,
      bandGains: flatGains,
      loudnessEnabled: false,
      loudnessGain: 0,
    );
  }

  final lowerBound = minDecibels;
  final upperBound = maxDecibels < lowerBound ? lowerBound : maxDecibels;
  final clampedGains = List<double>.generate(count, (index) {
    final rawGain = index < bandGains.length ? bandGains[index] : 0.0;
    return rawGain.clamp(lowerBound, upperBound).toDouble();
  });
  final headroom = clampedGains.fold<double>(0, max);
  final loudnessGain = min(
    headroom,
    JustAudioController._maxAndroidLoudnessCompensationDb,
  );
  final safeGains = headroom <= 0
      ? clampedGains
      : [
          for (final gain in clampedGains)
            (gain - headroom).clamp(lowerBound, 0.0).toDouble(),
        ];

  if (safeGains.every((gain) => gain.abs() < 0.01)) {
    return (
      equalizerEnabled: false,
      bandGains: flatGains,
      loudnessEnabled: false,
      loudnessGain: 0,
    );
  }
  return (
    equalizerEnabled: true,
    bandGains: safeGains,
    loudnessEnabled: loudnessGain > 0,
    loudnessGain: loudnessGain,
  );
}

Future<void> _disableAndroidLoudness({
  Future<void> Function(bool enabled)? setLoudnessEnabled,
  Future<void> Function(double gain)? setLoudnessGain,
  bool Function()? shouldContinue,
}) async {
  bool isCurrent() => shouldContinue?.call() ?? true;

  if (setLoudnessEnabled != null) {
    if (!isCurrent()) return;
    try {
      await setLoudnessEnabled(false);
    } catch (error) {
      debugPrint('JustAudioController Android loudness disable failed: $error');
    }
  }
  if (setLoudnessGain != null) {
    if (!isCurrent()) return;
    try {
      await setLoudnessGain(0);
    } catch (error) {
      debugPrint('JustAudioController Android loudness reset failed: $error');
    }
  }
}

Future<void> _enableAndroidLoudness({
  required double gain,
  required Future<void> Function(bool enabled)? setLoudnessEnabled,
  required Future<void> Function(double gain)? setLoudnessGain,
  required bool Function() shouldContinue,
}) async {
  if (setLoudnessEnabled == null || setLoudnessGain == null || gain <= 0) {
    return;
  }

  try {
    await setLoudnessGain(gain);
  } catch (error) {
    debugPrint('JustAudioController Android loudness gain failed: $error');
    return;
  }
  if (!shouldContinue()) return;

  try {
    await setLoudnessEnabled(true);
  } catch (error) {
    debugPrint('JustAudioController Android loudness enable failed: $error');
  }
}
