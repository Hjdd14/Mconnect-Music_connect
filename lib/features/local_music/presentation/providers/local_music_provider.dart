import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;
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
import '../../data/track_ratings_store.dart';
import '../../domain/local_library_dedupe.dart';
import '../../domain/local_library_grouping.dart';
import '../../domain/local_library_query.dart';

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

  /// What the page is searching/sorting/filtering by.
  ///
  /// An immutable value object, so the filtered list is a pure function of
  /// `(tracks, query, ratings, playCounts)` and can be asserted in a plain test.
  final LocalLibraryQuery query;

  /// `songKey` → rating; only **rated** songs are present.
  final Map<String, int> ratings;

  /// `songKey` → play count, aggregated from the play events (never a second
  /// counter that could disagree with the statistics page).
  final Map<String, int> playCounts;

  /// Rows ticked in multi-select mode. Empty means "not selecting".
  ///
  /// Paths rather than `Song`s or indexes: a path is the primary key of the
  /// local index, so a tick survives a re-sort or a rescan that reorders rows.
  final Set<String> selectedPaths;

  /// True while the page shows its multi-select chrome.
  ///
  /// Deliberately not derived from [selectedPaths]: "in selection mode with
  /// nothing ticked yet" is a real state — the action bar has to be on screen
  /// (so 全选 is reachable) before the first row is ticked.
  final bool selectionMode;

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
    this.query = LocalLibraryQuery.none,
    this.ratings = const {},
    this.playCounts = const {},
    this.selectedPaths = const {},
    this.selectionMode = false,
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
    LocalLibraryQuery? query,
    Map<String, int>? ratings,
    Map<String, int>? playCounts,
    Set<String>? selectedPaths,
    bool? selectionMode,
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
      query: query ?? this.query,
      ratings: ratings ?? this.ratings,
      playCounts: playCounts ?? this.playCounts,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      selectionMode: selectionMode ?? this.selectionMode,
    );
  }

  String? lyricsFor(String songId) => lyricsBySongId[songId];

  /// The local index after the query: keyword, then filters, then sort.
  ///
  /// Every view below derives from this one getter, so a filter cannot apply to
  /// the song list but silently not to the album list.
  List<LocalTrackEntry> get queriedTracks => query.apply(
    tracks,
    ratings: ratings,
    playCounts: playCounts,
  );

  /// The local songs after the query.
  ///
  /// Preferred source is [tracks] — the index rows the query can actually filter
  /// and sort. [songs] is the fallback for a state that was built without index
  /// rows (a preview, or a test constructing `LocalMusicState` directly to check
  /// the local/online merge): returning it unfiltered is strictly better than
  /// dropping the local list, and every production path sets both fields, so the
  /// two can never diverge in the app itself.
  List<Song> get queriedSongs => tracks.isEmpty
      ? songs
      : [for (final track in queriedTracks) track.toSong()];

  /// True when the user changed something, so the UI can offer "清除筛选".
  bool get isQueryActive => !query.isDefault;

  /// True while the page shows its multi-select chrome.
  ///
  /// [selectionMode] alone is enough (and is what makes 全选 reachable before the
  /// first tick); a non-empty [selectedPaths] also implies it, so a state that was
  /// built with ticks but no explicit mode still renders the bar.
  bool get isSelecting => selectionMode || selectedPaths.isNotEmpty;

  int get selectedCount => selectedPaths.length;

  /// The ticked rows, in library order (not in tap order) so a batch action
  /// reports a stable, predictable list.
  List<LocalTrackEntry> get selectedTracks => [
    for (final track in tracks)
      if (selectedPaths.contains(track.path)) track,
  ];

  /// The rating of one track, `0` when it was never rated.
  int ratingOf(LocalTrackEntry track) =>
      ratings[localTrackSongKey(track)] ?? 0;

  /// The song list actually rendered: with [mergeWithOnline] the (queried) local
  /// library is merged with the cached online library on [Song.dedupeKey], local
  /// first, so a song that exists in both places appears exactly once.
  List<Song> get visibleSongs => mergeWithOnline
      ? LocalLibraryDedupe.mergeLocalWithOnline(
          local: queriedSongs,
          online: onlineSongs,
        )
      : queriedSongs;

  List<LocalTrackGroup> get albumGroups =>
      LocalLibraryGrouping.byAlbum(queriedTracks);
  List<LocalTrackGroup> get artistGroups =>
      LocalLibraryGrouping.byArtist(queriedTracks);
  List<LocalTrackGroup> get folderGroups =>
      LocalLibraryGrouping.byFolder(queriedTracks);

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
  final TrackRatingsStore _ratingsStore;

  LocalMusicNotifier({
    LocalMusicRepository? repository,
    LocalMusicScanner? scanner,
    LocalMusicPicker? picker,
    LocalTrackStore? trackStore,
    LocalLyricsStore? lyricsStore,
    LocalScanRootStore? rootStore,
    OnlineLibrarySnapshot? onlineSnapshot,
    TrackRatingsStore? ratingsStore,
  }) : this._(
         scanner ?? repository ?? LocalMusicRepository(),
         picker,
         trackStore ?? DriftLocalTrackStore(),
         lyricsStore ?? DriftLocalLyricsStore(),
         rootStore ?? HiveLocalScanRootStore(),
         onlineSnapshot ?? DriftOnlineLibrarySnapshot(),
         ratingsStore ?? defaultTrackRatingsStore(),
       );

  LocalMusicNotifier._(
    this._scanner,
    LocalMusicPicker? picker,
    this._trackStore,
    this._lyricsStore,
    this._rootStore,
    this._onlineSnapshot,
    this._ratingsStore,
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
      // A ratings read must never take the library down with it: the tracks are
      // the feature, the stars are decoration. An empty map simply means "nothing
      // rated yet", which is also what a fresh install looks like.
      var ratings = const <String, int>{};
      var playCounts = const <String, int>{};
      try {
        ratings = await _ratingsStore.loadRatings();
        playCounts = await _ratingsStore.loadPlayCounts();
      } catch (e) {
        debugPrint('local ratings unavailable: $e');
      }
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
        ratings: ratings,
        playCounts: playCounts,
        isLoading: false,
        selectedDirectory: rememberedRoot,
        error: () => null,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: () => '读取本地曲库失败：$e');
    }
  }

  // --- Search / sort / filter ------------------------------------------------

  /// Replaces the keyword. The filtered list is derived, so only the query is
  /// stored — no second list to keep in sync.
  void setKeyword(String keyword) {
    state = state.copyWith(query: state.query.copyWith(keyword: keyword));
  }

  void setSort(LocalSortField sort) {
    state = state.copyWith(query: state.query.copyWith(sort: sort));
  }

  void setSortDescending(bool descending) {
    state = state.copyWith(
      query: state.query.copyWith(descending: descending),
    );
  }

  void toggleSortDirection() {
    setSortDescending(!state.query.descending);
  }

  void toggleFilter(LocalTrackFilter filter, bool enabled) {
    state = state.copyWith(
      query: state.query.withFilter(filter, enabled),
    );
  }

  void clearQuery() {
    state = state.copyWith(query: LocalLibraryQuery.none);
  }

  // --- Ratings ---------------------------------------------------------------

  /// Sets the rating for one local track and remembers it.
  ///
  /// The write is optimistic: the star must not lag behind the tap. A write that
  /// fails leaves the stored map as the truth, so the value comes back on the
  /// next load rather than being silently claimed as saved.
  Future<void> setRating(LocalTrackEntry track, int rating) async {
    final key = localTrackSongKey(track);
    final next = {...state.ratings};
    if (rating <= 0) {
      next.remove(key);
    } else {
      next[key] = rating.clamp(1, 5);
    }
    state = state.copyWith(ratings: next);
    try {
      await _ratingsStore.setRating(key, rating);
    } catch (e) {
      // Re-reading is the honest recovery: the UI must not keep showing a rating
      // the database refused.
      final stored = await _ratingsStore.loadRatings();
      if (!mounted) return;
      state = state.copyWith(ratings: stored, error: () => '保存评分失败：$e');
    }
  }

  /// Re-reads ratings and play counts (after a scan, and when the statistics
  /// page has recorded new plays).
  Future<void> refreshRatings() async {
    final ratings = await _ratingsStore.loadRatings();
    final playCounts = await _ratingsStore.loadPlayCounts();
    if (!mounted) return;
    state = state.copyWith(ratings: ratings, playCounts: playCounts);
  }

  /// Recomputes the materialised play aggregate. Cheap enough for a scan
  /// boundary, too expensive for a rebuild, which is why nothing else calls it.
  Future<void> syncPlayStats() async {
    await _ratingsStore.syncPlayStats();
    await refreshRatings();
  }

  // --- Multi-select and batch actions ---------------------------------------

  /// Enters or leaves multi-select. Leaving always drops the ticks, so the next
  /// entry starts clean instead of acting on a stale selection.
  void setSelectionMode(bool enabled) {
    if (enabled == state.selectionMode && (enabled || state.selectedPaths.isEmpty)) {
      return;
    }
    state = state.copyWith(
      selectionMode: enabled,
      selectedPaths: enabled ? state.selectedPaths : const {},
    );
  }

  void toggleSelected(String path) {
    final next = {...state.selectedPaths};
    if (!next.remove(path)) next.add(path);
    state = state.copyWith(selectedPaths: next);
  }

  /// Ticks every row currently visible (i.e. after the query), so "全选" means
  /// "all of what the user is looking at".
  void selectAllVisible() {
    state = state.copyWith(
      selectedPaths: {for (final track in state.queriedTracks) track.path},
    );
  }

  void clearSelection() {
    state = state.copyWith(selectedPaths: const {}, selectionMode: false);
  }

  /// Removes the ticked rows **from the library index only**.
  ///
  /// This is the one destructive batch action, and it deliberately cannot touch
  /// the user's audio: it deletes `local_tracks` rows (and their cached lyrics)
  /// and nothing else — no `File.delete`, no SAF delete, no path is ever handed
  /// to the filesystem. A removed row comes back on the next scan. That property
  /// is what makes the confirmation dialog honest when it says the audio file is
  /// untouched.
  ///
  /// Returns how many rows went away.
  Future<int> removeSelected() async {
    final paths = [for (final track in state.selectedTracks) track.path];
    if (paths.isEmpty) return 0;
    await _trackStore.removePaths(paths);
    // The lyrics cache is keyed by song id, which for a local track is its path.
    await _lyricsStore.removePaths(paths);
    if (!mounted) return paths.length;

    final removed = paths.toSet();
    final remaining = [
      for (final track in state.tracks)
        if (!removed.contains(track.path)) track,
    ];
    state = state.copyWith(
      tracks: remaining,
      songs: [for (final track in remaining) track.toSong()],
      selectedPaths: const {},
      selectionMode: false,
    );
    return paths.length;
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
    // A scan is the one moment where recomputing the materialised play aggregate
    // is worth its cost (one indexed `GROUP BY`): the counts are derived from the
    // play events, and this is when the library they belong to was just rebuilt.
    // Deliberately **not** awaited and deliberately not called from anywhere else:
    // a rebuild or a progress update would recompute a whole aggregate per frame.
    // Nothing depends on it having finished — the sort reads the live aggregate.
    unawaited(syncPlayStats());
  }
}

final localMusicProvider =
    StateNotifierProvider<LocalMusicNotifier, LocalMusicState>((ref) {
      final notifier = LocalMusicNotifier();
      unawaited(notifier.initialize());
      return notifier;
    });
