import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/diagnostics/diagnostics_service.dart';
import 'package:mconnect/core/platform/platform_utils.dart';
import 'package:mconnect/features/audio_effects/presentation/providers/audio_effects_provider.dart';
import 'package:just_audio/just_audio.dart' as just_audio;
import 'package:mconnect/features/player/presentation/providers/player_provider.dart';
import 'package:mconnect/features/player/data/playback_keep_alive_service.dart';
import 'package:mconnect/features/player/data/playback_notification_service.dart';
import 'package:mconnect/features/player/data/player_playback_memory_store.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/audio_quality.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/models/user.dart';
import 'package:mconnect/core/storage/session_storage.dart';
import 'package:mconnect/platform/base/music_platform.dart';

void main() {
  test('Windows does not create an Android equalizer', () {
    PlatformUtils.setDebugOverride(AppPlatform.windows);
    addTearDown(() => PlatformUtils.setDebugOverride(null));

    expect(createAndroidEqualizerForPlatform(), isNull);
  });

  test('non-Windows desktop does not create an Android equalizer', () {
    PlatformUtils.setDebugOverride(AppPlatform.linux);
    addTearDown(() => PlatformUtils.setDebugOverride(null));

    expect(createAndroidEqualizerForPlatform(), isNull);
  });

  test(
    'default construction does not eagerly create the audio controller',
    () async {
      var created = 0;
      final notifier = PlayerNotifier(
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () {
          created++;
          return _FakeAudioController();
        },
      );
      addTearDown(notifier.dispose);

      expect(notifier.state.currentSong, isNull);
      expect(created, 0);
    },
  );

  test(
    'playSong does not keep the audio mutex locked while play future is pending',
    () async {
      final audio = _FakeAudioController();
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () => _FakeAudioController(),
      );
      addTearDown(notifier.dispose);

      final playCall = notifier.playSong(_song('1'));
      await expectLater(
        playCall.timeout(const Duration(milliseconds: 200)),
        completes,
      );
      expect(audio.playCalls, 1);
      expect(notifier.state.isTransitioning, isFalse);

      final seekCall = notifier.seek(const Duration(seconds: 12));
      await expectLater(
        seekCall.timeout(const Duration(milliseconds: 200)),
        completes,
      );
      expect(audio.seekCalls, 1);
    },
  );

  test('playSong recovers when a finite audio operation hangs', () async {
    final hangingAudio = _FakeAudioController(hangOnStop: true);
    var recreated = 0;
    final notifier = PlayerNotifier(
      audioController: hangingAudio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioOperationTimeout: const Duration(milliseconds: 20),
      audioDisposeTimeout: const Duration(milliseconds: 20),
      audioControllerFactory: () {
        recreated++;
        return _FakeAudioController();
      },
    );
    addTearDown(notifier.dispose);

    await expectLater(
      notifier.playSong(_song('2')).timeout(const Duration(milliseconds: 250)),
      completes,
    );

    expect(recreated, greaterThanOrEqualTo(1));
    expect(notifier.state.isTransitioning, isFalse);
  });

  test('togglePlay does not wait for a pending play future', () async {
    final audio = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
    );
    addTearDown(notifier.dispose);

    await expectLater(
      notifier.togglePlay().timeout(const Duration(milliseconds: 200)),
      completes,
    );

    expect(audio.playCalls, 1);
  });

  test(
    'playSong keeps volume unchanged when fade is disabled by default',
    () async {
      final audio = _FakeAudioController();
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () => _FakeAudioController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('fade-disabled'));

      expect(audio.volumeChanges, isEmpty);
    },
  );

  test('fade option ramps volume on play and pause when enabled', () async {
    final audio = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
    );
    addTearDown(notifier.dispose);

    notifier.setFadeOptions(enabled: true, duration: Duration.zero);
    await notifier.playSong(_song('fade-enabled'));
    await pumpEventQueue();
    await notifier.togglePlay();

    expect(audio.volumeChanges, containsAllInOrder([0, 1, 0, 1]));
    expect(audio.pauseCalls, 1);
  });

  test(
    'ignores duplicate completed events while the next song is loading',
    () async {
      final audio = _FakeAudioController();
      final songTwoUrl = Completer<String>();
      final platform = _ControlledUrlPlatform(
        urls: {'transition-2': songTwoUrl.future},
      );
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => platform,
        audioControllerFactory: () => _FakeAudioController(),
      );
      addTearDown(notifier.dispose);

      final playlist = [
        _song('transition-1'),
        _song('transition-2'),
        _song('transition-3'),
      ];
      await notifier.playPlaylist(playlist);
      final nextCall = notifier.skipToNext();
      await pumpEventQueue();
      expect(notifier.state.currentSong?.id, 'transition-2');
      expect(notifier.state.isTransitioning, isTrue);

      audio.emitCompleted();
      songTwoUrl.complete('https://example.test/transition-2-low.mp3');
      await nextCall;
      await pumpEventQueue();

      expect(notifier.state.currentSong?.id, 'transition-2');
      expect(audio.lastUrl, contains('transition-2'));
    },
  );

  test(
    'cancels stale fades so an old pause cannot silence later playback',
    () async {
      final audio = _FakeAudioController();
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () => _FakeAudioController(),
      );
      addTearDown(notifier.dispose);

      notifier.setFadeOptions(
        enabled: true,
        duration: const Duration(milliseconds: 60),
      );
      await notifier.playSong(_song('fade-race-1'));
      final pauseCall = notifier.pause();
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await notifier.playSong(_song('fade-race-2'));
      await pauseCall;
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(audio.lastUrl, contains('fade-race-2'));
      expect(audio.volumeChanges.last, 1);
    },
  );

  test('equalizer settings are applied through the audio controller', () async {
    final audio = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      audioOperationTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(notifier.dispose);

    await notifier.applyEqualizerSettings(
      const AudioEffectsSettings(
        equalizerEnabled: true,
        equalizerPreset: EqualizerPreset.rock,
      ),
    );

    expect(audio.equalizerEnabledChanges, [true]);
    expect(audio.equalizerBandGainChanges, [
      const EqualizerBandGain(0, 4),
      const EqualizerBandGain(1, 2),
      const EqualizerBandGain(2, 0),
      const EqualizerBandGain(3, 3),
      const EqualizerBandGain(4, 5),
    ]);
  });

  test('playSong clears the loading state when audio reports ready', () async {
    final audio = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: audio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('3'));

    expect(notifier.state.isTransitioning, isFalse);
    expect(notifier.state.isPlaying, isTrue);
  });

  test(
    'syncs Android background playback state while playing changes',
    () async {
      final audio = _FakeAudioController();
      final notification = _FakePlaybackNotificationController();
      final keepAlive = _FakePlaybackKeepAliveController();
      final notifier = PlayerNotifier(
        audioController: audio,
        platformResolver: (_) => _FakeMusicPlatform(),
        audioControllerFactory: () => _FakeAudioController(),
        notificationController: notification,
        keepAliveController: keepAlive,
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('background-sync'));
      await notifier.pause();
      await pumpEventQueue();

      expect(keepAlive.playingStates, [true, false]);
      expect(notification.attached, isTrue);
      expect(notification.updates.last.isPlaying, isFalse);
      expect(notification.updates.last.currentSong?.id, 'background-sync');
    },
  );

  test('dispose detaches notification and releases playback keep alive', () {
    final notification = _FakePlaybackNotificationController();
    final keepAlive = _FakePlaybackKeepAliveController();
    final notifier = PlayerNotifier(
      audioController: _FakeAudioController(),
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
      notificationController: notification,
      keepAliveController: keepAlive,
    );

    notifier.dispose();

    expect(notification.detached, isTrue);
    expect(keepAlive.disposed, isTrue);
  });

  test('a hanging seek does not block playing another song', () async {
    final hangingSeekAudio = _FakeAudioController(hangOnSeek: true);
    final notifier = PlayerNotifier(
      audioController: hangingSeekAudio,
      platformResolver: (_) => _FakeMusicPlatform(),
      audioControllerFactory: () => _FakeAudioController(),
    );
    addTearDown(notifier.dispose);

    unawaited(notifier.seek(const Duration(seconds: 30)));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await expectLater(
      notifier
          .playSong(_song('seek-recovery'))
          .timeout(const Duration(milliseconds: 200)),
      completes,
    );
    expect(notifier.state.currentSong?.id, 'seek-recovery');
  });

  test('a hanging quality switch does not block play controls', () async {
    final switchCompleter = Completer<String>();
    final controller = _FakeAudioController();
    final notifier = PlayerNotifier(
      audioController: controller,
      audioControllerFactory: () => _FakeAudioController(),
      audioOperationTimeout: const Duration(milliseconds: 30),
      platformResolver: (_) => _QualityHangPlatform(
        normalUrl: 'https://example.test/song.mp3',
        qualityCompleter: switchCompleter,
      ),
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('quality-hang'));
    unawaited(notifier.switchQuality(AudioLevel.lossless));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await notifier.togglePlay().timeout(const Duration(milliseconds: 200));

    expect(notifier.state.isTransitioning, isFalse);
  });

  test('keeps a manually selected fixed quality for the next song', () async {
    final platform = _FakeMusicPlatform();
    final notifier = PlayerNotifier(
      audioController: _FakeAudioController(),
      platformResolver: (_) => platform,
      audioControllerFactory: () => _FakeAudioController(),
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('fixed-quality-1'));
    await notifier.switchQuality(AudioLevel.medium);
    await notifier.playSong(_song('fixed-quality-2'));

    expect(notifier.state.currentQuality, AudioLevel.medium);
    expect(
      platform.requestedQualitiesFor('fixed-quality-2'),
      contains(AudioLevel.medium),
    );
    expect(
      platform.requestedQualitiesFor('fixed-quality-2'),
      isNot(contains(AudioLevel.low)),
    );
  });

  test(
    'highest quality preference resolves each new song to its own highest quality',
    () async {
      final platform = _FakeMusicPlatform(
        qualitiesBySong: {
          'highest-1': const [
            AudioQuality(level: AudioLevel.low, bitrate: 128000, format: 'mp3'),
            AudioQuality(
              level: AudioLevel.lossless,
              bitrate: 999000,
              format: 'flac',
            ),
          ],
          'highest-2': const [
            AudioQuality(level: AudioLevel.low, bitrate: 128000, format: 'mp3'),
            AudioQuality(
              level: AudioLevel.master,
              bitrate: 3200000,
              format: 'flac',
            ),
          ],
        },
      );
      final notifier = PlayerNotifier(
        audioController: _FakeAudioController(),
        platformResolver: (_) => platform,
        audioControllerFactory: () => _FakeAudioController(),
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(_song('highest-1'));
      await notifier.switchQuality(AudioLevel.lossless, preferHighest: true);
      await notifier.playSong(_song('highest-2'));

      expect(notifier.state.currentQuality, AudioLevel.master);
      expect(notifier.state.qualityPreference, AudioQualityPreference.highest);
      expect(
        platform.requestedQualitiesFor('highest-2'),
        contains(AudioLevel.master),
      );
      expect(platform.availableQualityRequests, containsAll(['highest-2']));
    },
  );

  test('persists highest quality preference in playback memory', () async {
    final store = _MemoryPlaybackStore();
    final platform = _FakeMusicPlatform(
      qualitiesBySong: {
        'remember-highest': const [
          AudioQuality(level: AudioLevel.low, bitrate: 128000, format: 'mp3'),
          AudioQuality(
            level: AudioLevel.master,
            bitrate: 3200000,
            format: 'flac',
          ),
        ],
      },
    );
    final notifier = PlayerNotifier(
      audioController: _FakeAudioController(),
      audioControllerFactory: () => _FakeAudioController(),
      platformResolver: (_) => platform,
      playbackMemoryStore: store,
      playbackMemorySaveInterval: Duration.zero,
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('remember-highest'));
    await notifier.switchQuality(AudioLevel.master, preferHighest: true);

    expect(store.saved?.currentQuality, AudioLevel.master);
    expect(store.saved?.qualityPreference, AudioQualityPreference.highest);
  });

  test(
    'playSong plays local files without resolving a remote platform',
    () async {
      final audio = _FakeAudioController();
      final notifier = PlayerNotifier(
        audioController: audio,
        audioControllerFactory: () => _FakeAudioController(),
        platformResolver: (_) =>
            throw StateError('remote resolver should not be called'),
      );
      addTearDown(notifier.dispose);

      await notifier.playSong(
        _song('D:\\Music\\local.mp3', platform: PlatformType.local),
      );

      expect(audio.lastUrl, Uri.file('D:\\Music\\local.mp3').toString());
      expect(notifier.state.currentSong?.platform, PlatformType.local);
    },
  );

  test('persists the current song and playback position', () async {
    final store = _MemoryPlaybackStore();
    final notifier = PlayerNotifier(
      audioController: _FakeAudioController(),
      audioControllerFactory: () => _FakeAudioController(),
      platformResolver: (_) => _FakeMusicPlatform(),
      playbackMemoryStore: store,
      playbackMemorySaveInterval: Duration.zero,
    );
    addTearDown(notifier.dispose);

    await notifier.playSong(_song('remember-me'));
    await notifier.switchQuality(AudioLevel.medium);
    await notifier.seek(const Duration(minutes: 1, seconds: 23));

    expect(store.saved?.currentSong.id, 'remember-me');
    expect(store.saved?.position, const Duration(minutes: 1, seconds: 23));
    expect(store.saved?.currentQuality, AudioLevel.medium);
    expect(store.saved?.qualityPreference, AudioQualityPreference.fixed);
  });

  test('restores the last song and position without autoplay', () async {
    final store = _MemoryPlaybackStore(
      restored: PlayerPlaybackMemory(
        currentSong: _song('restored'),
        playlist: [_song('restored')],
        currentIndex: 0,
        position: const Duration(minutes: 2, seconds: 4),
        duration: const Duration(minutes: 4),
        currentQuality: AudioLevel.medium,
      ),
    );
    final notifier = PlayerNotifier(
      audioControllerFactory: () => _FakeAudioController(),
      platformResolver: (_) => _FakeMusicPlatform(),
      playbackMemoryStore: store,
      playbackMemorySaveInterval: Duration.zero,
    );
    addTearDown(notifier.dispose);

    await pumpEventQueue();

    expect(notifier.state.currentSong?.id, 'restored');
    expect(notifier.state.position, const Duration(minutes: 2, seconds: 4));
    expect(notifier.state.duration, const Duration(minutes: 4));
    expect(notifier.state.currentQuality, AudioLevel.medium);
    expect(notifier.state.isPlaying, isFalse);
  });

  test(
    'play after restore loads the source and resumes from the saved position',
    () async {
      final audio = _FakeAudioController();
      final store = _MemoryPlaybackStore(
        restored: PlayerPlaybackMemory(
          currentSong: _song('resume-me'),
          playlist: [_song('resume-me')],
          currentIndex: 0,
          position: const Duration(seconds: 42),
          duration: const Duration(minutes: 3),
          currentQuality: AudioLevel.low,
        ),
      );
      final notifier = PlayerNotifier(
        audioController: audio,
        audioControllerFactory: () => _FakeAudioController(),
        platformResolver: (_) => _FakeMusicPlatform(),
        playbackMemoryStore: store,
        playbackMemorySaveInterval: Duration.zero,
      );
      addTearDown(notifier.dispose);

      await pumpEventQueue();
      await notifier.togglePlay();

      expect(audio.lastUrl, 'https://example.test/resume-me-low.mp3');
      expect(audio.seekCalls, 1);
      expect(audio.position, const Duration(seconds: 42));
      expect(audio.playCalls, 1);
      expect(notifier.state.isPlaying, isTrue);
    },
  );
}

Song _song(String id, {PlatformType platform = PlatformType.netease}) => Song(
  id: id,
  platform: platform,
  name: 'song $id',
  artists: const [Artist(id: 'artist', name: 'artist')],
);

class _FakeAudioController implements PlayerAudioController {
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _playerStateController =
      StreamController<AudioPlaybackState>.broadcast();
  final Completer<void> _playCompleter = Completer<void>();
  final bool hangOnStop;
  final bool hangOnSeek;

  int playCalls = 0;
  int pauseCalls = 0;
  int seekCalls = 0;
  String? lastUrl;
  bool _playing = false;
  Duration _position = Duration.zero;
  final List<double> volumeChanges = [];
  final List<bool> equalizerEnabledChanges = [];
  final List<EqualizerBandGain> equalizerBandGainChanges = [];

  _FakeAudioController({this.hangOnStop = false, this.hangOnSeek = false});

  @override
  bool get playing => _playing;

  @override
  Duration get position => _position;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<AudioPlaybackState> get playerStateStream =>
      _playerStateController.stream;

  @override
  Future<void> stop() async {
    if (hangOnStop) {
      return Completer<void>().future;
    }
    _playing = false;
  }

  @override
  Future<void> setUrl(String url) async {
    lastUrl = url;
    _playerStateController.add(
      const AudioPlaybackState(
        playing: false,
        processingState: just_audio.ProcessingState.ready,
      ),
    );
  }

  @override
  Future<void> play() {
    playCalls++;
    _playing = true;
    _playerStateController.add(
      const AudioPlaybackState(
        playing: true,
        processingState: just_audio.ProcessingState.ready,
      ),
    );
    return _playCompleter.future;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _playing = false;
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
    if (hangOnSeek) {
      return Completer<void>().future;
    }
    _position = position;
  }

  @override
  Future<void> setVolume(double volume) async {
    volumeChanges.add(volume);
  }

  void emitCompleted() {
    _playing = false;
    _playerStateController.add(
      const AudioPlaybackState(
        playing: false,
        processingState: just_audio.ProcessingState.completed,
      ),
    );
  }

  @override
  Future<void> applyEqualizer({
    required bool enabled,
    required List<double> bandGains,
  }) async {
    equalizerEnabledChanges.add(enabled);
    for (var i = 0; i < bandGains.length; i++) {
      equalizerBandGainChanges.add(EqualizerBandGain(i, bandGains[i]));
    }
  }

  @override
  Future<void> dispose() async {
    await _positionController.close();
    await _durationController.close();
    await _playerStateController.close();
  }
}

class _FakePlaybackKeepAliveController implements PlaybackKeepAliveController {
  final List<bool> playingStates = [];
  bool disposed = false;

  @override
  Future<void> setPlaying(bool playing) async {
    playingStates.add(playing);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    playingStates.add(false);
  }
}

class _PlaybackNotificationUpdate {
  final Song? currentSong;
  final bool isPlaying;

  const _PlaybackNotificationUpdate({
    required this.currentSong,
    required this.isPlaying,
  });
}

class _FakePlaybackNotificationController
    implements PlaybackNotificationController {
  final List<_PlaybackNotificationUpdate> updates = [];
  bool attached = false;
  bool detached = false;

  @override
  Future<void> initialize({DiagnosticsService? diagnostics}) async {}

  @override
  void attach(PlaybackNotificationActions actions) {
    attached = true;
  }

  @override
  void detach() {
    detached = true;
  }

  @override
  void update({
    required Song? currentSong,
    required List<Song> playlist,
    required int currentIndex,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
  }) {
    updates.add(
      _PlaybackNotificationUpdate(
        currentSong: currentSong,
        isPlaying: isPlaying,
      ),
    );
  }
}

class _MemoryPlaybackStore implements PlayerPlaybackMemoryStore {
  PlayerPlaybackMemory? restored;
  PlayerPlaybackMemory? saved;

  _MemoryPlaybackStore({this.restored});

  @override
  Future<PlayerPlaybackMemory?> load() async => restored;

  @override
  Future<void> save(PlayerPlaybackMemory memory) async {
    saved = memory;
  }

  @override
  Future<void> clear() async {
    saved = null;
    restored = null;
  }
}

class _FakeMusicPlatform implements MusicPlatform {
  final Map<String, List<AudioQuality>> qualitiesBySong;
  final List<({String songId, AudioLevel quality})> requestedQualities = [];
  final List<String> availableQualityRequests = [];

  _FakeMusicPlatform({this.qualitiesBySong = const {}});

  List<AudioLevel> requestedQualitiesFor(String songId) => requestedQualities
      .where((request) => request.songId == songId)
      .map((request) => request.quality)
      .toList();

  @override
  PlatformType get platformType => PlatformType.netease;

  @override
  String get platformName => 'fake';

  @override
  bool get isLoggedIn => true;

  @override
  Future<void> saveSession(SessionStorage storage) async {}

  @override
  Future<void> restoreSession(SessionStorage storage) async {}

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) async {
    requestedQualities.add((songId: songId, quality: quality));
    return 'https://example.test/$songId-${quality.name}.mp3';
  }

  @override
  Future<List<AudioQuality>> getAvailableQualities(String songId) async {
    availableQualityRequests.add(songId);
    return qualitiesBySong[songId] ?? const [];
  }

  @override
  Future<QrLoginResult> getQrCode() {
    throw UnimplementedError();
  }

  @override
  Stream<QrLoginStatus> pollQrStatus(String key) {
    throw UnimplementedError();
  }

  @override
  Future<LoginResult> loginByPhone(String phone, String code) {
    throw UnimplementedError();
  }

  @override
  Future<LoginResult> sendPhoneCode(String phone) async =>
      const LoginResult(success: false, error: 'unsupported');

  @override
  Future<User?> getUserInfo() async => null;

  @override
  Future<void> logout() async {}

  @override
  Future<List<Song>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async => const [];

  @override
  Future<List<Playlist>> searchPlaylists(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async => const [];

  @override
  Future<String?> getLyrics(String songId) async => null;

  @override
  Future<List<Playlist>> getUserPlaylists() async => const [];

  @override
  Future<List<Song>> getPlaylistDetail(String playlistId) async => const [];

  @override
  Future<List<Song>> getLikedSongs() async => const [];

  @override
  Future<bool> likeSong(String songId, {bool like = true}) async => false;

  @override
  Future<bool> addSongToPlaylist(String playlistId, Song song) async => false;

  @override
  Future<Playlist?> createPlaylist(String name) async => null;

  @override
  Future<bool> collectPlaylist(
    String playlistId, {
    bool collect = true,
  }) async => false;

  @override
  Future<List<Song>> getDailyRecommendations() async => const [];

  @override
  Future<List<Song>> getRankingList() async => const [];

  @override
  Future<VipLevel> getVipStatus() async => VipLevel.free;

  @override
  Future<Playlist?> parseShareLink(String url) async => null;
}

class _QualityHangPlatform extends _FakeMusicPlatform {
  final String normalUrl;
  final Completer<String> qualityCompleter;

  _QualityHangPlatform({
    required this.normalUrl,
    required this.qualityCompleter,
  });

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) {
    if (quality == AudioLevel.lossless) {
      return qualityCompleter.future;
    }
    return Future.value(normalUrl);
  }
}

class _ControlledUrlPlatform extends _FakeMusicPlatform {
  final Map<String, Future<String>> urls;

  _ControlledUrlPlatform({required this.urls});

  @override
  Future<String> getSongUrl(
    String songId, {
    AudioLevel quality = AudioLevel.low,
  }) {
    final url = urls[songId];
    if (url != null) return url;
    return super.getSongUrl(songId, quality: quality);
  }
}
