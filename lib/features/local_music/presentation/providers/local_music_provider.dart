import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/platform/platform_utils.dart';
import '../../../../models/song.dart';
import '../../data/android_local_music_service.dart';
import '../../data/local_library_reconciler.dart';
import '../../data/local_lyrics_store.dart';
import '../../data/local_music_repository.dart';
import '../../data/local_scan_root_store.dart';
import '../../data/local_track_store.dart';
import '../../data/online_library_snapshot.dart';
import '../../domain/local_library_dedupe.dart';
import '../../domain/local_library_grouping.dart';

/// Which grouping the local page is showing.
enum LocalLibraryView { songs, albums, artists, folders }

class LocalMusicPickResult {
  final String selectedDirectory;
  final LocalMusicScanResult scanResult;

  const LocalMusicPickResult({
    required this.selectedDirectory,
    required this.scanResult,
  });
}

abstract class LocalMusicPicker {
  /// Opens the platform folder picker and scans whatever it returns.
  ///
  /// Implementations that need a persistable token (Android SAF) save it
  /// themselves, so the next page open can rescan without a picker.
  Future<LocalMusicPickResult?> pickAndScanDirectory();

  /// Rescans the previously chosen root without a picker, or `null` when this
  /// picker cannot (the desktop picker leaves that to [LocalMusicScanner]).
  Future<LocalMusicScanResult?> rescanSavedRoot() async => null;
}

class FilePickerLocalMusicPicker implements LocalMusicPicker {
  FilePickerLocalMusicPicker(this._scanner);

  final LocalMusicScanner _scanner;

  @override
  Future<LocalMusicPickResult?> pickAndScanDirectory() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select local music folder',
    );
    if (path == null || path.isEmpty) return null;
    final scanResult = await _scanner.scanDirectory(path);
    return LocalMusicPickResult(
      selectedDirectory: path,
      scanResult: scanResult,
    );
  }

  @override
  Future<LocalMusicScanResult?> rescanSavedRoot() async => null;
}

/// Android SAF picker: scans the picked tree, remembers the tree URI, and can
/// rescan that tree later without asking the user again.
class AndroidSafLocalMusicPicker implements LocalMusicPicker {
  AndroidSafLocalMusicPicker({
    AndroidLocalMusicService? service,
    LocalTrackStore? trackStore,
    LocalLyricsStore? lyricsStore,
    LocalScanRootStore? rootStore,
  }) : _service = service ?? AndroidLocalMusicService.instance,
       _trackStore = trackStore ?? DriftLocalTrackStore(),
       _lyricsStore = lyricsStore ?? DriftLocalLyricsStore(),
       _rootStore = rootStore ?? HiveLocalScanRootStore();

  final AndroidLocalMusicService _service;
  final LocalTrackStore _trackStore;
  final LocalLyricsStore _lyricsStore;
  final LocalScanRootStore _rootStore;

  @override
  Future<LocalMusicPickResult?> pickAndScanDirectory() async {
    final known = await _knownSnapshot();
    final payload = await _service.pickAndScanDirectory(known: known);
    if (payload == null) return null;
    final result = await _reconcile(payload);
    final treeUri = payload.treeUri;
    if (treeUri != null) {
      await _rootStore.write(treeUri);
    }
    return LocalMusicPickResult(
      selectedDirectory: payload.selectedDirectory,
      scanResult: result,
    );
  }

  @override
  Future<LocalMusicScanResult?> rescanSavedRoot() async {
    final root = await _rootStore.read();
    if (root == null || root.isEmpty) return null;
    final known = await _knownSnapshot();
    final payload = await _service.rescanDirectory(root, known: known);
    if (payload == null) return null;
    return _reconcile(payload);
  }

  Future<Map<String, List<int>>> _knownSnapshot() async {
    final index = await _trackStore.loadIndex();
    return {
      for (final entry in index.values) entry.path: [entry.mtime, entry.size],
    };
  }

  Future<LocalMusicScanResult> _reconcile(
    AndroidLocalMusicScanPayload payload,
  ) async {
    final decoded = payload.decodeLyrics();
    final reconciler = LocalLibraryReconciler(
      trackStore: _trackStore,
      lyricsStore: _lyricsStore,
    );
    return reconciler.reconcile(
      rootPath: payload.treeUri ?? payload.selectedDirectory,
      files: payload.files,
      skippedFiles: [...payload.skippedFiles, ...decoded.rejectedLyrics],
      resolvedLyrics: decoded.resolved,
    );
  }
}

LocalMusicPicker defaultLocalMusicPicker(
  LocalMusicScanner scanner, {
  LocalTrackStore? trackStore,
  LocalLyricsStore? lyricsStore,
  LocalScanRootStore? rootStore,
}) {
  return PlatformUtils.isAndroid
      ? AndroidSafLocalMusicPicker(
          trackStore: trackStore,
          lyricsStore: lyricsStore,
          rootStore: rootStore,
        )
      : FilePickerLocalMusicPicker(scanner);
}

class LocalMusicState {
  final List<Song> songs;
  final List<LocalTrackEntry> tracks;
  final Map<String, String> lyricsBySongId;
  final List<String> skippedFiles;
  final bool isScanning;
  final bool isLoading;
  final String? selectedDirectory;
  final String? error;

  /// Counters from the last scan, surfaced in the UI ("复用 998 / 解析 2").
  final LocalMusicScanResult? lastScan;

  /// The cached online library, used for dedupe.
  final List<Song> onlineSongs;

  /// When true the list shows local + online-only songs, one row per song.
  final bool mergeWithOnline;

  final LocalLibraryView view;

  const LocalMusicState({
    this.songs = const [],
    this.tracks = const [],
    this.lyricsBySongId = const {},
    this.skippedFiles = const [],
    this.isScanning = false,
    this.isLoading = false,
    this.selectedDirectory,
    this.error,
    this.lastScan,
    this.onlineSongs = const [],
    this.mergeWithOnline = false,
    this.view = LocalLibraryView.songs,
  });

  LocalMusicState copyWith({
    List<Song>? songs,
    List<LocalTrackEntry>? tracks,
    Map<String, String>? lyricsBySongId,
    List<String>? skippedFiles,
    bool? isScanning,
    bool? isLoading,
    String? selectedDirectory,
    String? Function()? error,
    LocalMusicScanResult? lastScan,
    List<Song>? onlineSongs,
    bool? mergeWithOnline,
    LocalLibraryView? view,
  }) {
    return LocalMusicState(
      songs: songs ?? this.songs,
      tracks: tracks ?? this.tracks,
      lyricsBySongId: lyricsBySongId ?? this.lyricsBySongId,
      skippedFiles: skippedFiles ?? this.skippedFiles,
      isScanning: isScanning ?? this.isScanning,
      isLoading: isLoading ?? this.isLoading,
      selectedDirectory: selectedDirectory ?? this.selectedDirectory,
      error: error != null ? error() : this.error,
      lastScan: lastScan ?? this.lastScan,
      onlineSongs: onlineSongs ?? this.onlineSongs,
      mergeWithOnline: mergeWithOnline ?? this.mergeWithOnline,
      view: view ?? this.view,
    );
  }

  String? lyricsFor(String songId) => lyricsBySongId[songId];

  /// The song list actually rendered: with [mergeWithOnline] the local library
  /// is merged with the cached online library on [Song.dedupeKey], local first,
  /// so a song that exists in both places appears exactly once.
  List<Song> get visibleSongs => mergeWithOnline
      ? LocalLibraryDedupe.mergeLocalWithOnline(
          local: songs,
          online: onlineSongs,
        )
      : songs;

  List<LocalTrackGroup> get albumGroups => LocalLibraryGrouping.byAlbum(tracks);
  List<LocalTrackGroup> get artistGroups => LocalLibraryGrouping.byArtist(tracks);
  List<LocalTrackGroup> get folderGroups => LocalLibraryGrouping.byFolder(tracks);

  /// Dedupe keys of the cached online library, computed once per call.
  ///
  /// Callers render a long list, so they take this set and reuse it per row —
  /// calling [isAlsoOnline] for every row would rebuild it once per row and
  /// turn a 1000-track list into a million string comparisons per build.
  Set<String> get onlineKeys =>
      onlineSongs.isEmpty ? const {} : LocalLibraryDedupe.keysOf(onlineSongs);

  /// True when [song] is also present in the cached online library.
  bool isAlsoOnline(Song song) =>
      onlineSongs.isNotEmpty && onlineKeys.contains(song.dedupeKey);
}

class LocalMusicNotifier extends StateNotifier<LocalMusicState> {
  final LocalMusicScanner _scanner;
  final LocalMusicPicker _picker;
  final LocalTrackStore _trackStore;
  final LocalLyricsStore _lyricsStore;
  final LocalScanRootStore _rootStore;
  final OnlineLibrarySnapshot _onlineSnapshot;

  LocalMusicNotifier({
    LocalMusicRepository? repository,
    LocalMusicScanner? scanner,
    LocalMusicPicker? picker,
    LocalTrackStore? trackStore,
    LocalLyricsStore? lyricsStore,
    LocalScanRootStore? rootStore,
    OnlineLibrarySnapshot? onlineSnapshot,
  }) : this._(
         scanner ?? repository ?? LocalMusicRepository(),
         picker,
         trackStore ?? DriftLocalTrackStore(),
         lyricsStore ?? DriftLocalLyricsStore(),
         rootStore ?? HiveLocalScanRootStore(),
         onlineSnapshot ?? DriftOnlineLibrarySnapshot(),
       );

  LocalMusicNotifier._(
    this._scanner,
    LocalMusicPicker? picker,
    this._trackStore,
    this._lyricsStore,
    this._rootStore,
    this._onlineSnapshot,
  ) : _picker =
          picker ??
          defaultLocalMusicPicker(
            _scanner,
            trackStore: _trackStore,
            lyricsStore: _lyricsStore,
            rootStore: _rootStore,
          ),
      super(const LocalMusicState());

  /// Loads the persisted index into state without touching the filesystem.
  ///
  /// This is what makes reopening the page instant: the library is already in
  /// the database, so there is nothing to rescan before showing it. The
  /// remembered folder (a path on desktop, a SAF tree URI on Android) is
  /// restored too, so the header is right before any rescan starts.
  Future<void> loadFromIndex() async {
    state = state.copyWith(isLoading: true, error: () => null);
    try {
      final tracks = await _trackStore.loadAll();
      final storedLyrics = await _lyricsStore.loadAll();
      final rememberedRoot = state.selectedDirectory ?? await _rootStore.read();
      if (!mounted) return;
      tracks.sort(
        (a, b) => a.displayTitle.toLowerCase().compareTo(
          b.displayTitle.toLowerCase(),
        ),
      );
      state = state.copyWith(
        tracks: tracks,
        songs: [for (final track in tracks) track.toSong()],
        lyricsBySongId: storedLyrics,
        isLoading: false,
        selectedDirectory: rememberedRoot,
        error: () => null,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: () => '读取本地曲库失败：$e');
    }
  }

  /// Startup path used by the page: show the persisted library, then refresh it
  /// incrementally if a root was remembered.
  Future<void> initialize() async {
    await loadFromIndex();
    if (!mounted) return;
    final root = await _rootStore.read();
    if (root != null && root.isNotEmpty) {
      final directory = state.selectedDirectory;
      state = state.copyWith(selectedDirectory: directory ?? root);
      await rescan();
    }
  }

  /// Rescans the remembered root. Unchanged files are skipped, so this is a
  /// stat-only walk when nothing changed.
  Future<void> rescan() async {
    final savedRoot = await _rootStore.read();
    state = state.copyWith(isScanning: true, error: () => null);
    try {
      final result =
          await _picker.rescanSavedRoot() ??
          (savedRoot == null || savedRoot.isEmpty
              ? null
              : await _scanner.scanDirectory(savedRoot));
      if (!mounted) return;
      if (result == null) {
        state = state.copyWith(isScanning: false);
        return;
      }
      _applyScanResult(result, directory: state.selectedDirectory ?? savedRoot);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isScanning: false, error: () => '本地音乐扫描失败：$e');
    }
  }

  Future<void> pickAndScanDirectory() async {
    state = state.copyWith(isScanning: true, error: () => null);
    try {
      final result = await _picker.pickAndScanDirectory();
      if (!mounted) return;
      if (result == null) {
        state = state.copyWith(isScanning: false);
        return;
      }
      // Desktop picks a real directory; Android hands back a SAF tree URI that
      // the picker already persisted on its own.
      if (!PlatformUtils.isAndroid) {
        await _rootStore.write(result.selectedDirectory);
      }
      _applyScanResult(
        result.scanResult,
        directory: result.selectedDirectory,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isScanning: false, error: () => '本地音乐扫描失败：$e');
    }
  }

  Future<void> scanDirectory(String path) async {
    state = state.copyWith(
      isScanning: true,
      selectedDirectory: path,
      error: () => null,
    );
    try {
      final result = await _scanner.scanDirectory(path);
      if (!mounted) return;
      _applyScanResult(result, directory: path);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isScanning: false, error: () => '本地音乐扫描失败：$e');
    }
  }

  /// Switches the local page between 歌曲 / 专辑 / 歌手 / 文件夹.
  void setView(LocalLibraryView view) {
    if (state.view == view) return;
    state = state.copyWith(view: view);
  }

  /// Turns local-vs-online dedupe on or off; enabling loads the online snapshot.
  Future<void> setMergeWithOnline(bool enabled) async {
    state = state.copyWith(mergeWithOnline: enabled);
    if (!enabled || state.onlineSongs.isNotEmpty) return;
    try {
      final online = await _onlineSnapshot.load();
      if (!mounted) return;
      state = state.copyWith(onlineSongs: online);
    } catch (_) {
      // Dedupe is a convenience: a failed snapshot simply leaves the local
      // library alone instead of surfacing a second error state.
    }
  }

  void _applyScanResult(LocalMusicScanResult result, {String? directory}) {
    // `/`-normalised for display; the stored value stays as the platform
    // reported it (a SAF URI is not a path).
    final display = directory == null || directory.isEmpty
        ? result.rootPath
        : directory;
    state = state.copyWith(
      songs: result.songs,
      tracks: result.tracks,
      lyricsBySongId: result.lyricsBySongId,
      skippedFiles: result.skippedFiles,
      isScanning: false,
      isLoading: false,
      selectedDirectory: display,
      lastScan: result,
      error: () => null,
    );
  }
}

final localMusicProvider =
    StateNotifierProvider<LocalMusicNotifier, LocalMusicState>((ref) {
      final notifier = LocalMusicNotifier();
      unawaited(notifier.initialize());
      return notifier;
    });
