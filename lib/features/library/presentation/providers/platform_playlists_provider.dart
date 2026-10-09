import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/network/platform_http.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/playlist.dart';
import '../../../../models/song.dart';
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

  /// Reported when the platform answers that the stored cookie is dead, so the
  /// app can drop the stale session instead of showing it as a network error.
  /// Test seam only: production leaves this null.
  ///
  /// v1.4.1 moved session-expiry handling to the network layer
  /// (`SessionExpiryReporter` → `lib/app.dart`), which covers every caller
  /// instead of only this one. Wiring it here *as well* produced two
  /// `handleSessionExpired` calls for a single 401, i.e. two "session expired"
  /// toasts, so the production wiring was removed and only the message below
  /// stays local.
  final void Function(PlatformType platform)? onSessionExpired;
  final Map<PlatformType, int> _loadTokens = {};
  int _nextLoadToken = 0;

  PlatformPlaylistsNotifier({
    List<PlatformType>? supportedTypes,
    MusicPlatform Function(PlatformType)? platformResolver,
    this._operationTimeout = const Duration(seconds: 8),
    this.onSessionExpired,
  })  : _supportedTypes = (() => supportedTypes ?? PlatformType.musicServices),
        _platformResolver = platformResolver ?? PlatformRegistry.get,
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
      if (apiExceptionOf(e) is LoginExpiredException) {
        // Session clearing is reported centrally by the network layer
        // (SessionExpiryReporter); this branch only picks the page's wording.
        onSessionExpired?.call(platformType);
        error = '登录已过期，请重新登录';
      } else {
        error = '加载失败：$e';
      }
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

  /// Fetches one playlist's songs, for "copy to a local playlist".
  ///
  /// Read-only, so it works even on platforms whose write endpoints are not
  /// available — the copy itself is created locally and needs no platform write.
  /// Returns an empty list on any failure; the caller reports it rather than
  /// creating an empty copy.
  Future<List<Song>> loadSongs(Playlist playlist) async {
    try {
      final platform = _platformResolver(playlist.platform);
      if (!platform.isLoggedIn) return const [];
      return await platform
          .getPlaylistDetail(playlist.id)
          .timeout(_operationTimeout, onTimeout: () => const <Song>[]);
    } catch (_) {
      return const [];
    }
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
  // NOTE: session expiry is deliberately NOT wired here any more. The network
  // layer reports it centrally (see `SessionExpiryReporter` and `lib/app.dart`),
  // and wiring it here as well made a single 401 expire the session twice and
  // raise the "session expired" toast twice.
  return PlatformPlaylistsNotifier();
});
