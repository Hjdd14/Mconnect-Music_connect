import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/platform/platform_utils.dart';
import '../../../../models/song.dart';
import '../../data/android_local_music_service.dart';
import '../../data/local_music_repository.dart';

class LocalMusicPickResult {
  final String selectedDirectory;
  final LocalMusicScanResult scanResult;

  const LocalMusicPickResult({
    required this.selectedDirectory,
    required this.scanResult,
  });
}

abstract class LocalMusicPicker {
  Future<LocalMusicPickResult?> pickAndScanDirectory();
}

class FilePickerLocalMusicPicker implements LocalMusicPicker {
  final LocalMusicScanner _scanner;

  const FilePickerLocalMusicPicker(this._scanner);

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
}

class AndroidSafLocalMusicPicker implements LocalMusicPicker {
  final AndroidLocalMusicService _service;

  AndroidSafLocalMusicPicker({AndroidLocalMusicService? service})
    : _service = service ?? AndroidLocalMusicService.instance;

  @override
  Future<LocalMusicPickResult?> pickAndScanDirectory() async {
    final result = await _service.pickAndScanDirectory();
    if (result == null) return null;
    return LocalMusicPickResult(
      selectedDirectory: result.selectedDirectory,
      scanResult: result.scanResult,
    );
  }
}

LocalMusicPicker defaultLocalMusicPicker(LocalMusicScanner scanner) {
  return PlatformUtils.isAndroid
      ? AndroidSafLocalMusicPicker()
      : FilePickerLocalMusicPicker(scanner);
}

class LocalMusicState {
  final List<Song> songs;
  final Map<String, String> lyricsBySongId;
  final List<String> skippedFiles;
  final bool isScanning;
  final String? selectedDirectory;
  final String? error;

  const LocalMusicState({
    this.songs = const [],
    this.lyricsBySongId = const {},
    this.skippedFiles = const [],
    this.isScanning = false,
    this.selectedDirectory,
    this.error,
  });

  LocalMusicState copyWith({
    List<Song>? songs,
    Map<String, String>? lyricsBySongId,
    List<String>? skippedFiles,
    bool? isScanning,
    String? selectedDirectory,
    String? Function()? error,
  }) {
    return LocalMusicState(
      songs: songs ?? this.songs,
      lyricsBySongId: lyricsBySongId ?? this.lyricsBySongId,
      skippedFiles: skippedFiles ?? this.skippedFiles,
      isScanning: isScanning ?? this.isScanning,
      selectedDirectory: selectedDirectory ?? this.selectedDirectory,
      error: error != null ? error() : this.error,
    );
  }

  String? lyricsFor(String songId) => lyricsBySongId[songId];
}

class LocalMusicNotifier extends StateNotifier<LocalMusicState> {
  final LocalMusicScanner _scanner;
  final LocalMusicPicker _picker;

  LocalMusicNotifier({
    LocalMusicRepository? repository,
    LocalMusicScanner? scanner,
    LocalMusicPicker? picker,
  }) : this._(scanner ?? repository ?? LocalMusicRepository(), picker);

  LocalMusicNotifier._(LocalMusicScanner scanner, LocalMusicPicker? picker)
    : _scanner = scanner,
      _picker = picker ?? defaultLocalMusicPicker(scanner),
      super(const LocalMusicState());

  Future<void> pickAndScanDirectory() async {
    state = state.copyWith(isScanning: true, error: () => null);
    try {
      final result = await _picker.pickAndScanDirectory();
      if (!mounted) return;
      if (result == null) {
        state = state.copyWith(isScanning: false);
        return;
      }
      state = state.copyWith(
        songs: result.scanResult.songs,
        lyricsBySongId: result.scanResult.lyricsBySongId,
        skippedFiles: result.scanResult.skippedFiles,
        isScanning: false,
        selectedDirectory: result.selectedDirectory,
        error: () => null,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isScanning: false,
        error: () => 'Local music scan failed: $e',
      );
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
      state = state.copyWith(
        songs: result.songs,
        lyricsBySongId: result.lyricsBySongId,
        skippedFiles: result.skippedFiles,
        isScanning: false,
        error: () => null,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isScanning: false,
        error: () => 'Local music scan failed: $e',
      );
    }
  }
}

final localMusicProvider =
    StateNotifierProvider<LocalMusicNotifier, LocalMusicState>((ref) {
      return LocalMusicNotifier();
    });
