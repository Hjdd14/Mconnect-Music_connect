import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:mconnect/features/player/data/media_kit_windows_audio_controller.dart';
import 'package:mconnect/features/player/data/player_audio_controller.dart';

void main() {
  test('Windows equalizer builds a five band mpv audio filter', () {
    final filter = MediaKitWindowsAudioController.equalizerFilterForTest(
      enabled: true,
      bandGains: const [6, 0, -3, 2, 12],
    );

    expect(
      filter,
      'lavfi=[equalizer=f=60:t=q:w=1:g=6,'
      'equalizer=f=230:t=q:w=1:g=0,'
      'equalizer=f=910:t=q:w=1:g=-3,'
      'equalizer=f=3600:t=q:w=1:g=2,'
      'equalizer=f=14000:t=q:w=1:g=12,'
      'volume=-12dB]',
    );
  });

  test('Windows equalizer clears the filter when disabled or flat', () {
    expect(
      MediaKitWindowsAudioController.equalizerFilterForTest(
        enabled: false,
        bandGains: const [6, 0, -3, 2, 12],
      ),
      '',
    );
    expect(
      MediaKitWindowsAudioController.equalizerFilterForTest(
        enabled: true,
        bandGains: const [0, 0, 0, 0, 0],
      ),
      '',
    );
  });

  test(
    'Windows controller maps volume and equalizer to media_kit backend',
    () async {
      final backend = _FakeMediaKitWindowsBackend();
      final controller = MediaKitWindowsAudioController(
        backendFactory: () => backend,
      );
      addTearDown(controller.dispose);

      await controller.setVolume(0.42);
      await controller.applyEqualizer(
        enabled: true,
        bandGains: const [4, 2, 0, 3, 5],
      );

      expect(backend.volumeChanges, [42.0]);
      expect(backend.audioFilters, [
        'lavfi=[equalizer=f=60:t=q:w=1:g=4,'
            'equalizer=f=230:t=q:w=1:g=2,'
            'equalizer=f=910:t=q:w=1:g=0,'
            'equalizer=f=3600:t=q:w=1:g=3,'
            'equalizer=f=14000:t=q:w=1:g=5,'
            'volume=-5dB]',
      ]);
    },
  );

  test('Windows controller maps backend playback state streams', () async {
    final backend = _FakeMediaKitWindowsBackend();
    final controller = MediaKitWindowsAudioController(
      backendFactory: () => backend,
    );
    addTearDown(controller.dispose);
    final states = <AudioPlaybackState>[];
    final sub = controller.playerStateStream.listen(states.add);
    addTearDown(sub.cancel);

    await controller.setUrl('https://example.test/song.mp3');
    backend.emitBuffering(true);
    await pumpEventQueue();
    backend.emitPlaying(true);
    await pumpEventQueue();
    backend.emitCompleted(true);
    await pumpEventQueue();

    expect(
      states.map((state) => state.processingState),
      containsAllInOrder([
        just_audio.ProcessingState.ready,
        just_audio.ProcessingState.buffering,
        just_audio.ProcessingState.ready,
        just_audio.ProcessingState.completed,
      ]),
    );
    expect(states.any((state) => state.playing), isTrue);
  });

  test(
    'Windows local file setUrl publishes a known duration after open',
    () async {
      final backend = _FakeMediaKitWindowsBackend(
        durationAfterOpen: const Duration(minutes: 3, seconds: 21),
      );
      final controller = MediaKitWindowsAudioController(
        backendFactory: () => backend,
      );
      addTearDown(controller.dispose);
      final durations = <Duration?>[];
      final sub = controller.durationStream.listen(durations.add);
      addTearDown(sub.cancel);

      await controller.setUrl('file:///D:/Music/local-song.mp3');
      await pumpEventQueue();

      expect(durations, contains(const Duration(minutes: 3, seconds: 21)));
    },
  );

  test(
    'Windows remote setUrl does not probe backend duration synchronously',
    () async {
      final backend = _FakeMediaKitWindowsBackend(
        durationAfterOpen: const Duration(minutes: 4),
      );
      final controller = MediaKitWindowsAudioController(
        backendFactory: () => backend,
      );
      addTearDown(controller.dispose);

      await controller.setUrl('https://example.test/song.mp3');

      expect(backend.durationReadCount, 0);
    },
  );

  test(
    'Windows controller exposes backend errors and clears playing state',
    () async {
      final backend = _FakeMediaKitWindowsBackend();
      final controller = MediaKitWindowsAudioController(
        backendFactory: () => backend,
      );
      addTearDown(controller.dispose);
      final states = <AudioPlaybackState>[];
      final errors = <Object>[];
      final sub = controller.playerStateStream.listen(
        states.add,
        onError: errors.add,
      );
      addTearDown(sub.cancel);

      await controller.setUrl('https://example.test/song.mp3');
      backend.emitPlaying(true);
      await pumpEventQueue();
      backend.emitError('libmpv missing');
      await pumpEventQueue();

      expect(errors.single.toString(), contains('libmpv missing'));
      expect(states.last.playing, isFalse);
      expect(states.last.processingState, just_audio.ProcessingState.idle);
    },
  );
}

class _FakeMediaKitWindowsBackend implements MediaKitWindowsBackend {
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _bufferingController = StreamController<bool>.broadcast();
  final _completedController = StreamController<bool>.broadcast();
  final _errorController = StreamController<Object>.broadcast();
  final Duration durationAfterOpen;
  final List<double> volumeChanges = [];
  final List<String> audioFilters = [];
  int durationReadCount = 0;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  _FakeMediaKitWindowsBackend({this.durationAfterOpen = Duration.zero});

  @override
  bool get playing => _playing;

  @override
  Duration get position => _position;

  @override
  Duration get duration {
    durationReadCount++;
    return _duration;
  }

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Stream<bool> get bufferingStream => _bufferingController.stream;

  @override
  Stream<bool> get completedStream => _completedController.stream;

  @override
  Stream<Object> get errorStream => _errorController.stream;

  void emitPlaying(bool value) {
    _playing = value;
    _playingController.add(value);
  }

  void emitBuffering(bool value) {
    _bufferingController.add(value);
  }

  void emitCompleted(bool value) {
    _completedController.add(value);
  }

  void emitError(Object value) {
    _playing = false;
    _errorController.add(value);
  }

  @override
  Future<void> open(String url) async {
    _duration = durationAfterOpen;
  }

  @override
  Future<void> play() async {
    emitPlaying(true);
  }

  @override
  Future<void> pause() async {
    emitPlaying(false);
  }

  @override
  Future<void> stop() async {
    emitPlaying(false);
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _positionController.add(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    volumeChanges.add(volume);
  }

  @override
  Future<void> setAudioFilter(String filter) async {
    audioFilters.add(filter);
  }

  @override
  Future<void> dispose() async {
    await _positionController.close();
    await _durationController.close();
    await _playingController.close();
    await _bufferingController.close();
    await _completedController.close();
    await _errorController.close();
  }
}
