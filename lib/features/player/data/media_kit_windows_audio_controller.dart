import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:media_kit/media_kit.dart' as media_kit;

import 'player_audio_controller.dart';

abstract class MediaKitWindowsBackend {
  bool get playing;
  Duration get position;
  Duration get duration;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<bool> get completedStream;
  Stream<Object> get errorStream;

  Future<void> open(String url);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setAudioFilter(String filter);
  Future<void> dispose();
}

class MediaKitWindowsAudioController implements PlayerAudioController {
  static const _frequencies = [60, 230, 910, 3600, 14000];

  final MediaKitWindowsBackend Function() _backendFactory;
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _playerStateController =
      StreamController<AudioPlaybackState>.broadcast();
  final List<StreamSubscription> _subscriptions = [];
  MediaKitWindowsBackend? _backend;
  bool _playing = false;
  bool _buffering = false;
  bool _completed = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  MediaKitWindowsAudioController({
    MediaKitWindowsBackend Function()? backendFactory,
  }) : _backendFactory = backendFactory ?? RealMediaKitWindowsBackend.create;

  @visibleForTesting
  static String equalizerFilterForTest({
    required bool enabled,
    required List<double> bandGains,
  }) {
    return _equalizerFilter(enabled: enabled, bandGains: bandGains);
  }

  @override
  bool get playing => _backend?.playing ?? _playing;

  @override
  Duration get position => _backend?.position ?? _position;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<AudioPlaybackState> get playerStateStream =>
      _playerStateController.stream;

  @override
  Future<void> setUrl(String url) async {
    final backend = _ensureBackend();
    _completed = false;
    await backend.open(url);
    await _publishKnownLocalDuration(backend, url);
    _emitPlaybackState();
  }

  @override
  Future<void> play() async {
    final backend = _ensureBackend();
    await backend.play();
    _playing = true;
    _completed = false;
    _emitPlaybackState();
  }

  @override
  Future<void> pause() async {
    final backend = _ensureBackend();
    await backend.pause();
    _playing = false;
    _emitPlaybackState();
  }

  @override
  Future<void> stop() async {
    final backend = _ensureBackend();
    await backend.stop();
    _playing = false;
    _completed = false;
    _position = Duration.zero;
    _emitPlaybackState(processingState: just_audio.ProcessingState.idle);
  }

  @override
  Future<void> seek(Duration position) async {
    final backend = _ensureBackend();
    await backend.seek(position);
    _position = position;
    _positionController.add(position);
  }

  @override
  Future<void> setVolume(double volume) {
    final backend = _ensureBackend();
    return backend.setVolume(volume.clamp(0.0, 1.0) * 100);
  }

  @override
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> bandGains,
  }) {
    final backend = _ensureBackend();
    return backend.setAudioFilter(
      _equalizerFilter(enabled: enabled, bandGains: bandGains),
    );
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _backend?.dispose();
    _backend = null;
    await _positionController.close();
    await _durationController.close();
    await _playerStateController.close();
  }

  MediaKitWindowsBackend _ensureBackend() {
    final existing = _backend;
    if (existing != null) return existing;
    final backend = _backendFactory();
    _backend = backend;
    _subscriptions
      ..add(
        backend.positionStream.listen((position) {
          _position = position;
          _positionController.add(position);
        }),
      )
      ..add(
        backend.durationStream.listen((duration) {
          _emitDuration(duration);
        }),
      )
      ..add(
        backend.playingStream.listen((playing) {
          _playing = playing;
          if (playing) {
            _completed = false;
            _buffering = false;
          }
          _emitPlaybackState();
        }),
      )
      ..add(
        backend.bufferingStream.listen((buffering) {
          _buffering = buffering;
          _emitPlaybackState();
        }),
      )
      ..add(
        backend.completedStream.listen((completed) {
          _completed = completed;
          if (completed) {
            _playing = false;
            _buffering = false;
          }
          _emitPlaybackState();
        }),
      );
    _subscriptions.add(
      backend.errorStream.listen((error) {
        _playing = false;
        _buffering = false;
        _completed = false;
        if (!_playerStateController.isClosed) {
          _playerStateController.addError(error);
        }
        _emitPlaybackState(processingState: just_audio.ProcessingState.idle);
      }),
    );
    return backend;
  }

  Future<void> _publishKnownLocalDuration(
    MediaKitWindowsBackend backend,
    String url,
  ) async {
    if (_localFilePathFromUrl(url) == null) return;

    final immediate = backend.duration;
    if (immediate > Duration.zero) {
      _emitDuration(immediate);
      return;
    }

    try {
      final duration = await backend.durationStream
          .firstWhere((value) => value > Duration.zero)
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => backend.duration,
          );
      if (duration > Duration.zero) {
        _emitDuration(duration);
      }
    } catch (_) {
      final current = backend.duration;
      if (current > Duration.zero) {
        _emitDuration(current);
      }
    }
  }

  void _emitDuration(Duration duration) {
    if (_durationController.isClosed || _duration == duration) return;
    _duration = duration;
    _durationController.add(duration);
  }

  void _emitPlaybackState({just_audio.ProcessingState? processingState}) {
    if (_playerStateController.isClosed) return;
    _playerStateController.add(
      AudioPlaybackState(
        playing: _playing,
        processingState:
            processingState ??
            (_completed
                ? just_audio.ProcessingState.completed
                : _buffering
                ? just_audio.ProcessingState.buffering
                : just_audio.ProcessingState.ready),
      ),
    );
  }

  static String _equalizerFilter({
    required bool enabled,
    required List<double> bandGains,
  }) {
    if (!enabled) return '';
    final gains = List<double>.generate(_frequencies.length, (index) {
      final value = index < bandGains.length ? bandGains[index] : 0;
      return value.clamp(-12.0, 12.0).toDouble();
    });
    if (gains.every((gain) => gain.abs() < 0.01)) return '';
    final filters = <String>[
      for (var i = 0; i < _frequencies.length; i++)
        'equalizer=f=${_frequencies[i]}:t=q:w=1:g=${_formatDb(gains[i])}',
    ];
    final maxPositiveGain = gains.fold<double>(0, max);
    if (maxPositiveGain > 0) {
      filters.add('volume=-${_formatDb(maxPositiveGain)}dB');
    }
    return 'lavfi=[${filters.join(',')}]';
  }

  static String _formatDb(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.01) {
      return rounded.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }
}

class RealMediaKitWindowsBackend implements MediaKitWindowsBackend {
  final media_kit.Player _player;

  RealMediaKitWindowsBackend._(this._player);

  static RealMediaKitWindowsBackend create() {
    media_kit.MediaKit.ensureInitialized();
    return RealMediaKitWindowsBackend._(media_kit.Player());
  }

  @override
  bool get playing => _player.state.playing;

  @override
  Duration get position => _player.state.position;

  @override
  Duration get duration => _player.state.duration;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<Object> get errorStream => _player.stream.error;

  @override
  Future<void> open(String url) async {
    final path = _localFilePathFromUrl(url);
    if (path != null && !File(path).existsSync()) {
      throw StateError('Local music file not found: $path');
    }
    await _player.open(media_kit.Media(url), play: false);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setAudioFilter(String filter) async {
    final platform = _player.platform;
    if (platform is media_kit.NativePlayer) {
      await platform.setProperty('af', filter);
    }
  }

  @override
  Future<void> dispose() => _player.dispose();
}

String? _localFilePathFromUrl(String url) {
  if (url.startsWith(RegExp(r'^[a-zA-Z]:[\\/]')) || url.startsWith(r'\\')) {
    return url;
  }
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'file') return null;
  try {
    return uri.toFilePath(windows: Platform.isWindows);
  } catch (_) {
    return null;
  }
}
