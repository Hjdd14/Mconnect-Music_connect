import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:mconnect/features/player/presentation/providers/lyrics_provider.dart';
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/player/presentation/widgets/lyrics_display.dart';
import 'package:mconnect/lyrics/models/lyrics_line.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';

void main() {
  testWidgets('lyrics display scrolls down when playback reaches later lines', (
    tester,
  ) async {
    final notifier = _LyricsTestPlayerNotifier();
    final document = LyricsDocument(
      lines: List.generate(
        40,
        (index) => LyricsLine(
          timestamp: Duration(seconds: index),
          text: 'Line $index',
        ),
      ),
      format: LyricsFormat.lrc,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) => notifier),
          lyricsProvider.overrideWith((ref) async => document),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SizedBox(height: 240, child: LyricsDisplay())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, 0);

    notifier.setProgress(const Duration(seconds: 24));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
  });
}

const _song = Song(
  id: 'lyrics-song',
  platform: PlatformType.netease,
  name: 'Lyrics Song',
  artists: [Artist(id: 'artist', name: 'Artist')],
);

class _LyricsTestPlayerNotifier extends PlayerNotifier {
  _LyricsTestPlayerNotifier()
    : super(
        audioController: _IdleAudioController(),
        audioControllerFactory: () => _IdleAudioController(),
      ) {
    state = state.copyWith(
      currentSong: _song,
      playlist: const [_song],
      currentIndex: 0,
      position: Duration.zero,
      duration: const Duration(minutes: 3),
    );
  }

  void setProgress(Duration position) {
    state = state.copyWith(position: position);
  }
}

class _IdleAudioController implements PlayerAudioController {
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _playerStateController =
      StreamController<AudioPlaybackState>.broadcast();

  @override
  bool get playing => false;

  @override
  Duration get position => Duration.zero;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<AudioPlaybackState> get playerStateStream =>
      _playerStateController.stream;

  @override
  Future<void> stop() async {}

  @override
  Future<void> setUrl(String url) async {}

  @override
  Future<void> play() async {
    _playerStateController.add(
      const AudioPlaybackState(
        playing: true,
        processingState: just_audio.ProcessingState.ready,
      ),
    );
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> bandGains,
  }) async {}

  @override
  Future<void> dispose() async {
    await _positionController.close();
    await _durationController.close();
    await _playerStateController.close();
  }
}
