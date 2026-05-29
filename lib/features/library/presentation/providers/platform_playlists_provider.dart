import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/playlist.dart';
import '../../../../platform/base/music_platform.dart';
import '../../../../platform/base/platform_registry.dart';

class PlatformPlaylistsState {
  final Map<PlatformType, List<Playlist>> playlistsByPlatform;
  final Map<PlatformType, String> errorsByPlatform;
  final Map<PlatformType, bool> loadingByPlatform;
  final Map<PlatformType, bool> creatingByPlatform;

  const PlatformPlaylistsState({
    this.playlistsByPlatform = const {},
    this.errorsByPlatform = const {},
    this.loadingByPlatform = const {},
    this.creatingByPlatform = const {},
  });

  bool get isLoading => loadingByPlatform.values.any((loading) => loading);

  bool isLoadingFor(PlatformType platform) =>
      loadingByPlatform[platform] ?? false;

  bool isCreatingFor(PlatformType platform) =>
      creatingByPlatform[platform] ?? false;

  PlatformPlaylistsState copyWith({
    Map<PlatformType, List<Playlist>>? playlistsByPlatform,
    Map<PlatformType, String>? errorsByPlatform,
    Map<PlatformType, bool>? loadingByPlatform,
    Map<PlatformType, bool>? creatingByPlatform,
  }) {
    return PlatformPlaylistsState(
      playlistsByPlatform: playlistsByPlatform ?? this.playlistsByPlatform,
      errorsByPlatform: errorsByPlatform ?? this.errorsByPlatform,
      loadingByPlatform: loadingByPlatform ?? this.loadingByPlatform,
      creatingByPlatform: creatingByPlatform ?? this.creatingByPlatform,
    );
  }

  List<Playlist> playlistsFor(PlatformType platform) =>
      playlistsByPlatform[platform] ?? const [];
}

class PlatformPlaylistsNotifier extends StateNotifier<PlatformPlaylistsState> {
  final List<PlatformType> Function() _supportedTypes;
  final MusicPlatform Function(PlatformType) _platformResolver;
  final Duration _operationTimeout;
  final Map<PlatformType, int> _loadTokens = {};
  int _nextLoadToken = 0;

  PlatformPlaylistsNotifier({
    List<PlatformType>? supportedTypes,
    MusicPlatform Function(PlatformType)? platformResolver,
    Duration operationTimeout = const Duration(seconds: 8),
  })  : _supportedTypes = (() => supportedTypes ?? PlatformType.musicServices),
        _platformResolver = platformResolver ?? PlatformRegistry.get,
        _operationTimeout = operationTimeout,
        super(const PlatformPlaylistsState());

  Future<void> load() async {
    final types = _supportedTypes();
    if (types.isEmpty) {
      state = const PlatformPlaylistsState();
      return;
    }

    await Future.wait(types.map(loadPlatform));
  }

  Future<void> loadPlatform(PlatformType platformType) async {
    final token = ++_nextLoadToken;
    _loadTokens[platformType] = token;
    _setPlatformLoading(platformType, true);

    var playlists = const <Playlist>[];
    String? error;

    try {
      final platform = _platformResolver(platformType);
      if (platform.isLoggedIn) {
        playlists = await platform.getUserPlaylists().timeout(
          _operationTimeout,
          onTimeout: () => throw TimeoutException(
            '${platformType.displayName}歌单加载超时',
            _operationTimeout,
          ),
        );
        playlists = _routeablePlaylists(playlists);
      }
    } on TimeoutException {
      error = '加载超时，请稍后重试';
    } catch (e) {
      error = '加载失败：$e';
    }

    if (!mounted || _loadTokens[platformType] != token) return;

    final nextErrors = {...state.errorsByPlatform};
    if (error == null) {
      nextErrors.remove(platformType);
    } else {
      nextErrors[platformType] = error;
    }

    state = state.copyWith(
      playlistsByPlatform: {
        ...state.playlistsByPlatform,
        platformType: playlists,
      },
      errorsByPlatform: nextErrors,
      loadingByPlatform: {
        ...state.loadingByPlatform,
        platformType: false,
      },
    );
  }

  Future<Playlist?> create(PlatformType platformType, String name) async {
    _setPlatformCreating(platformType, true);

    Playlist? playlist;
    String? error;
    try {
      final platform = _platformResolver(platformType);
      if (!platform.isLoggedIn) {
        error = '请先登录${platformType.displayName}账号';
      } else {
        playlist = await platform.createPlaylist(name).timeout(
          _operationTimeout,
          onTimeout: () => null,
        );
        if (playlist == null) {
          error = '新建歌单失败';
        } else if (playlist.id.trim().isEmpty) {
          playlist = null;
          error = '新建歌单失败：平台未返回可访问的歌单ID';
        }
      }
    } catch (e) {
      error = '新建歌单失败：$e';
    }

    if (!mounted) return null;

    final nextErrors = {...state.errorsByPlatform};
    if (error == null) {
      nextErrors.remove(platformType);
    } else {
      nextErrors[platformType] = error;
    }

    _setPlatformCreating(platformType, false, errors: nextErrors);
    if (playlist == null) return null;

    final current = state.playlistsFor(platformType);
    state = state.copyWith(
      playlistsByPlatform: {
        ...state.playlistsByPlatform,
        platformType: [playlist, ...current],
      },
    );
    return playlist;
  }

  List<Playlist> _routeablePlaylists(List<Playlist> playlists) {
    return playlists.where((playlist) => playlist.id.trim().isNotEmpty).toList();
  }

  void _setPlatformLoading(PlatformType platformType, bool loading) {
    if (!mounted) return;
    final nextErrors = {...state.errorsByPlatform};
    if (loading) nextErrors.remove(platformType);
    state = state.copyWith(
      errorsByPlatform: nextErrors,
      loadingByPlatform: {
        ...state.loadingByPlatform,
        platformType: loading,
      },
    );
  }

  void _setPlatformCreating(
    PlatformType platformType,
    bool creating, {
    Map<PlatformType, String>? errors,
  }) {
    if (!mounted) return;
    state = state.copyWith(
      errorsByPlatform: errors ?? state.errorsByPlatform,
      creatingByPlatform: {
        ...state.creatingByPlatform,
        platformType: creating,
      },
    );
  }
}

final platformPlaylistsProvider =
    StateNotifierProvider<PlatformPlaylistsNotifier, PlatformPlaylistsState>((ref) {
  return PlatformPlaylistsNotifier();
});
