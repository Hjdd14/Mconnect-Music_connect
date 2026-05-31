import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/playlist.dart';
import '../../../../models/song.dart';
import '../../data/my_playlists_repository.dart';

class MyPlaylistsState {
  final List<Playlist> playlists;
  final bool isLoading;
  final bool isSaving;
  final String? error;

  const MyPlaylistsState({
    this.playlists = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.error,
  });

  MyPlaylistsState copyWith({
    List<Playlist>? playlists,
    bool? isLoading,
    bool? isSaving,
    String? Function()? error,
  }) {
    return MyPlaylistsState(
      playlists: playlists ?? this.playlists,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      error: error != null ? error() : this.error,
    );
  }
}

class MyPlaylistsNotifier extends StateNotifier<MyPlaylistsState> {
  final MyPlaylistsRepository _repository;

  MyPlaylistsNotifier({MyPlaylistsRepository? repository})
    : _repository = repository ?? const MyPlaylistsRepository(),
      super(const MyPlaylistsState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: () => null);
    try {
      final playlists = await _repository.getPlaylists();
      if (!mounted) return;
      state = state.copyWith(
        playlists: playlists,
        isLoading: false,
        error: () => null,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: () => '加载我的歌单失败：$e');
    }
  }

  Future<Playlist?> create(String name) async {
    if (state.isSaving) return null;
    state = state.copyWith(isSaving: true, error: () => null);
    try {
      final playlist = await _repository.createPlaylist(name);
      final playlists = await _repository.getPlaylists();
      if (!mounted) return playlist;
      state = state.copyWith(
        playlists: playlists,
        isSaving: false,
        error: () => null,
      );
      return playlist;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isSaving: false, error: () => '新建我的歌单失败：$e');
      }
      return null;
    }
  }

  Future<Playlist?> importPlaylist({
    required String name,
    required List<Song> songs,
  }) async {
    if (state.isSaving) return null;
    state = state.copyWith(isSaving: true, error: () => null);
    try {
      final playlist = await _repository.importPlaylist(
        name: name,
        songs: songs,
      );
      final playlists = await _repository.getPlaylists();
      if (!mounted) return playlist;
      state = state.copyWith(
        playlists: playlists,
        isSaving: false,
        error: () => null,
      );
      return playlist;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isSaving: false, error: () => '保存导入歌单失败：$e');
      }
      return null;
    }
  }

  Future<bool> addSong(String playlistId, Song song) async {
    if (state.isSaving) return false;
    state = state.copyWith(isSaving: true, error: () => null);
    try {
      final ok = await _repository.addSong(playlistId, song);
      final playlists = await _repository.getPlaylists();
      if (mounted) {
        state = state.copyWith(
          playlists: playlists,
          isSaving: false,
          error: ok ? () => null : () => '歌单不存在',
        );
      }
      return ok;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isSaving: false, error: () => '添加到我的歌单失败：$e');
      }
      return false;
    }
  }

  Future<List<Song>> getSongs(String playlistId) {
    return _repository.getSongs(playlistId);
  }

  Future<bool> removeSong(String playlistId, Song song) async {
    if (state.isSaving) return false;
    state = state.copyWith(isSaving: true, error: () => null);
    try {
      final ok = await _repository.removeSong(playlistId, song);
      final playlists = await _repository.getPlaylists();
      if (mounted) {
        state = state.copyWith(
          playlists: playlists,
          isSaving: false,
          error: ok ? () => null : () => '歌曲不存在',
        );
      }
      return ok;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isSaving: false, error: () => '删除歌曲失败：$e');
      }
      return false;
    }
  }

  Future<bool> deletePlaylist(String playlistId) async {
    if (state.isSaving) return false;
    state = state.copyWith(isSaving: true, error: () => null);
    try {
      final ok = await _repository.deletePlaylist(playlistId);
      final playlists = await _repository.getPlaylists();
      if (mounted) {
        state = state.copyWith(
          playlists: playlists,
          isSaving: false,
          error: ok ? () => null : () => '歌单不存在',
        );
      }
      return ok;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isSaving: false, error: () => '删除歌单失败：$e');
      }
      return false;
    }
  }

  Future<String?> exportPlaylistLink(String playlistId) {
    return _repository.exportPlaylistLink(playlistId);
  }

  Future<Playlist?> importShareLink(String link) async {
    if (state.isSaving) return null;
    state = state.copyWith(isSaving: true, error: () => null);
    try {
      final playlist = await _repository.importShareLink(link);
      final playlists = await _repository.getPlaylists();
      if (mounted) {
        state = state.copyWith(
          playlists: playlists,
          isSaving: false,
          error: playlist == null ? () => '无法识别 Mconnect 歌单链接' : () => null,
        );
      }
      return playlist;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          isSaving: false,
          error: () => '导入 Mconnect 歌单失败：$e',
        );
      }
      return null;
    }
  }
}

final myPlaylistsProvider =
    StateNotifierProvider<MyPlaylistsNotifier, MyPlaylistsState>((ref) {
      return MyPlaylistsNotifier();
    });
