import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
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
      state = state.copyWith(
        isLoading: false,
        error: () => '加载我的歌单失败：$e',
      );
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
        state = state.copyWith(
          isSaving: false,
          error: () => '新建我的歌单失败：$e',
        );
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
      final playlist = await _repository.importPlaylist(name: name, songs: songs);
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
        state = state.copyWith(
          isSaving: false,
          error: () => '保存导入歌单失败：$e',
        );
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
        state = state.copyWith(
          isSaving: false,
          error: () => '添加到我的歌单失败：$e',
        );
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
        state = state.copyWith(
          isSaving: false,
          error: () => '删除歌曲失败：$e',
        );
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
        state = state.copyWith(
          isSaving: false,
          error: () => '删除歌单失败：$e',
        );
      }
      return false;
    }
  }

  /// Creates a local playlist from an already-fetched song list.
  ///
  /// Used by "copy a platform playlist": the songs are read from the platform and
  /// written locally, so no platform *write* capability is required.
  Future<Playlist?> copySongsToLocal({
    required String name,
    required List<Song> songs,
  }) async {
    if (state.isSaving) return null;
    state = state.copyWith(isSaving: true, error: () => null);
    try {
      final created = await _repository.importPlaylist(
        name: name,
        songs: songs,
      );
      final playlists = await _repository.getPlaylists();
      if (mounted) {
        state = state.copyWith(playlists: playlists, isSaving: false);
      }
      return created;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          isSaving: false,
          error: () => zhAppLocalizations.libraryPlaylistCopyError('$e'),
        );
      }
      return null;
    }
  }

  Future<String?> exportPlaylistLink(String playlistId) {
    return _repository.exportPlaylistLink(playlistId);
  }

  /// Renames a local playlist and refreshes the list so the new name shows.
  Future<bool> renamePlaylist(String playlistId, String newName) async {
    if (state.isSaving) return false;
    state = state.copyWith(isSaving: true, error: () => null);
    try {
      final ok = await _repository.renamePlaylist(playlistId, newName);
      final playlists = await _repository.getPlaylists();
      if (mounted) {
        state = state.copyWith(
          playlists: playlists,
          isSaving: false,
          error: ok ? () => null : () => _renameFailedMessage,
        );
      }
      return ok;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          isSaving: false,
          error: () => zhAppLocalizations.libraryPlaylistRenameError('$e'),
        );
      }
      return false;
    }
  }

  /// Copies a local playlist (songs included) and refreshes the list.
  Future<Playlist?> duplicatePlaylist(String playlistId) async {
    if (state.isSaving) return null;
    state = state.copyWith(isSaving: true, error: () => null);
    try {
      final copy = await _repository.duplicatePlaylist(
      playlistId,
      nameSuffix: zhAppLocalizations.libraryPlaylistCopy,
    );
      final playlists = await _repository.getPlaylists();
      if (mounted) {
        state = state.copyWith(
          playlists: playlists,
          isSaving: false,
          error: copy == null ? () => _duplicateFailedMessage : () => null,
        );
      }
      return copy;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          isSaving: false,
          error: () => zhAppLocalizations.libraryPlaylistCopyError('$e'),
        );
      }
      return null;
    }
  }

  // Localised through `zhAppLocalizations` — the same "no BuildContext" source
  // `lib/core/network/api_exception.dart` uses. This provider has no context, and
  // the i18n ratchet counts every hard-coded Chinese literal, so the strings come
  // from the ARB rather than being inlined here.
  String get _renameFailedMessage =>
      zhAppLocalizations.libraryPlaylistRenameFailed;
  String get _duplicateFailedMessage =>
      zhAppLocalizations.libraryPlaylistDuplicateFailed;

  /// Persists a new song order for [playlistId] (drag-to-reorder) and returns
  /// whether the write succeeded.
  ///
  /// Deliberately **not** gated on [MyPlaylistsState.isSaving] and does not set
  /// it: the list UI reorders optimistically while a download or playlist
  /// operation may be in flight, and dropping the user's drag because an
  /// unrelated write is running would look like the app lost the change. The
  /// repository replaces the whole order in one atomic write, so it cannot
  /// interleave with itself.
  Future<bool> reorderSongs(String playlistId, List<Song> ordered) async {
    try {
      final ok = await _repository.reorderSongs(playlistId, ordered);
      if (mounted && !ok) {
        state = state.copyWith(error: () => '歌单不存在');
      }
      return ok;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: () => '调整歌单顺序失败：$e');
      }
      return false;
    }
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
