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
  final AudioPlayer _player;
  final AndroidEqualizer? _equalizer;

  JustAudioController([AudioPlayer? player, AndroidEqualizer? equalizer])
    : this._(player, equalizer ?? createAndroidEqualizerForPlatform());

  JustAudioController._(AudioPlayer? player, AndroidEqualizer? equalizer)
    : _equalizer = equalizer,
      _player =
          player ??
          AudioPlayer(
            audioPipeline: equalizer == null
                ? null
                : AudioPipeline(androidAudioEffects: [equalizer]),
          );

  AudioPlayer get player => _player;

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
    if (equalizer == null) return;
    await equalizer.setEnabled(enabled);
    if (!enabled) return;
    final parameters = await equalizer.parameters;
    final count = min(parameters.bands.length, bandGains.length);
    for (var i = 0; i < count; i++) {
      final gain = bandGains[i].clamp(
        parameters.minDecibels,
        parameters.maxDecibels,
      );
      await parameters.bands[i].setGain(gain.toDouble());
    }
  }

  @override
  Future<void> dispose() => _player.dispose();
}

@visibleForTesting
AndroidEqualizer? createAndroidEqualizerForPlatform() {
  return PlatformUtils.isAndroid ? AndroidEqualizer() : null;
}
