import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/platform_type.dart';
import '../../../../models/toplist.dart';
import '../../../../platform/base/music_platform.dart';
import '../../../../platform/base/platform_registry.dart';
import '../../data/toplists_cache_store.dart';

/// QQ 音乐 热歌榜（`topId=26`, 300 tracks).
///
/// Pinned to the top of the hub because it is the chart the user asked for by
/// name; the id used to be wrong (`4`, which is 流行指数榜) in the platform
/// adapter, which is why "QQ 热歌榜没有入口" was reported.
const String qqHotToplistId = '26';
const String qqHotToplistName = '热歌榜';

/// Chart hub state: every chart of every platform, with per-platform errors.
///
/// Why per-platform errors: the removed `rankingsProvider` (deleted in v1.4.1)
/// dropped a platform entirely when its call failed (`if (songs.isNotEmpty)` +
/// an empty `catch`), so a QQ failure made the QQ tab silently disappear — half
/// of the reported "QQ 榜没有入口". Every platform now always appears in the
/// state, with either charts or an error message.
class ToplistsState {
  final Map<PlatformType, List<Toplist>> toplistsByPlatform;
  final Map<PlatformType, String> errorsByPlatform;

  /// Platforms whose current rows came from the offline cache because the
  /// refresh failed (or has not run yet).
  final Map<PlatformType, bool> offlineByPlatform;

  final bool isLoading;

  /// Platforms that were queried at all.
  final List<PlatformType> platforms;

  const ToplistsState({
    this.toplistsByPlatform = const {},
    this.errorsByPlatform = const {},
    this.offlineByPlatform = const {},
    this.isLoading = false,
    this.platforms = const [],
  });

  ToplistsState copyWith({
    Map<PlatformType, List<Toplist>>? toplistsByPlatform,
    Map<PlatformType, String>? errorsByPlatform,
    Map<PlatformType, bool>? offlineByPlatform,
    bool? isLoading,
    List<PlatformType>? platforms,
  }) {
    return ToplistsState(
      toplistsByPlatform: toplistsByPlatform ?? this.toplistsByPlatform,
      errorsByPlatform: errorsByPlatform ?? this.errorsByPlatform,
      offlineByPlatform: offlineByPlatform ?? this.offlineByPlatform,
      isLoading: isLoading ?? this.isLoading,
      platforms: platforms ?? this.platforms,
    );
  }

  List<Toplist> toplistsForPlatform(PlatformType platform) =>
      toplistsByPlatform[platform] ?? const [];

  String? errorForPlatform(PlatformType platform) =>
      errorsByPlatform[platform];

  bool isOffline(PlatformType platform) => offlineByPlatform[platform] ?? false;

  /// The QQ 热歌榜 entry from the loaded catalogue, when QQ answered.
  Toplist? get qqHotToplist {
    for (final toplist in toplistsForPlatform(PlatformType.qq)) {
      if (toplist.id == qqHotToplistId) return toplist;
    }
    return null;
  }

  /// A chart's metadata regardless of platform, used by the detail page header
  /// (`ListName` / 封面 / 更新频率 / 榜单定义).
  Toplist? findToplist(PlatformType platform, String toplistId) {
    for (final toplist in toplistsForPlatform(platform)) {
      if (toplist.id == toplistId) return toplist;
    }
    return null;
  }

  bool get hasAnyData => toplistsByPlatform.values.any((l) => l.isNotEmpty);

  int get totalCount =>
      toplistsByPlatform.values.fold(0, (sum, list) => sum + list.length);
}

class ToplistsNotifier extends StateNotifier<ToplistsState> {
  final List<PlatformType> Function() _supportedTypes;
  final MusicPlatform Function(PlatformType) _platformResolver;
  final ToplistsCacheStore? cache;
  final Duration operationTimeout;

  ToplistsNotifier({
    List<PlatformType>? supportedTypes,
    MusicPlatform Function(PlatformType)? platformResolver,
    this.cache,
    this.operationTimeout = const Duration(seconds: 15),
  }) : _supportedTypes = (() =>
           supportedTypes ?? PlatformRegistry.supportedTypes),
       _platformResolver = platformResolver ?? PlatformRegistry.get,
       super(const ToplistsState());

  /// Offline-first load: the cached catalogue is published immediately, then
  /// every platform is refreshed concurrently.
  ///
  /// A platform that fails keeps its cached rows and gets an error entry, so the
  /// hub never silently loses a platform.
  Future<void> load() async {
    state = state.copyWith(isLoading: true, errorsByPlatform: const {});

    final implementations = _implementations();
    final platforms = [for (final impl in implementations) impl.platformType];
    await _publishCache(platforms);

    final results = await Future.wait(implementations.map(_loadPlatform));
    if (!mounted) return;

    final toplists = Map<PlatformType, List<Toplist>>.from(
      state.toplistsByPlatform,
    );
    final errors = Map<PlatformType, String>.from(state.errorsByPlatform);
    final offline = Map<PlatformType, bool>.from(state.offlineByPlatform);

    for (final result in results) {
      if (result.toplists.isNotEmpty) {
        toplists[result.platform] = result.toplists;
        offline[result.platform] = false;
        errors.remove(result.platform);
      } else if (result.error != null) {
        // Keep whatever the cache produced; label it as offline instead of
        // dropping the platform.
        errors[result.platform] = result.error!;
        offline[result.platform] = toplists[result.platform]?.isNotEmpty ?? false;
      }
    }

    state = state.copyWith(
      toplistsByPlatform: toplists,
      errorsByPlatform: errors,
      offlineByPlatform: offline,
      isLoading: false,
    );
  }

  /// Network-only refresh (pull-to-refresh). Same error semantics as [load].
  Future<void> refresh() => load();

  /// Resolves every music-service platform exactly once per load.
  List<MusicPlatform> _implementations() {
    final implementations = <MusicPlatform>[];
    for (final type in _supportedTypes()) {
      if (!type.isMusicService) continue;
      try {
        implementations.add(_platformResolver(type));
      } catch (_) {
        continue;
      }
    }
    return implementations;
  }

  Future<void> _publishCache(List<PlatformType> platforms) async {
    final cache = this.cache;
    if (cache == null) return;
    try {
      final cached = await cache.all();
      if (!mounted) return;
      final toplists = <PlatformType, List<Toplist>>{};
      final offline = <PlatformType, bool>{};
      for (final platform in platforms) {
        final rows = cached[platform] ?? const <Toplist>[];
        if (rows.isEmpty) continue;
        toplists[platform] = rows;
        offline[platform] = true;
      }
      if (toplists.isEmpty) return;
      state = state.copyWith(
        toplistsByPlatform: toplists,
        offlineByPlatform: offline,
        platforms: platforms,
      );
    } catch (_) {
      // A cache read must never keep the hub from loading online data.
    }
  }

  Future<_PlatformToplists> _loadPlatform(MusicPlatform impl) async {
    final platform = impl.platformType;
    try {
      final toplists = await impl.getToplists().timeout(operationTimeout);
      await cache?.saveForPlatform(platform, toplists);
      return _PlatformToplists(platform: platform, toplists: toplists);
    } on TimeoutException {
      return _PlatformToplists(platform: platform, error: '请求超时');
    } catch (e) {
      return _PlatformToplists(
        platform: platform,
        error: e is Exception ? '$e' : '加载失败',
      );
    }
  }
}

class _PlatformToplists {
  final PlatformType platform;
  final List<Toplist> toplists;
  final String? error;

  const _PlatformToplists({
    required this.platform,
    this.toplists = const [],
    this.error,
  });
}

final toplistsCacheStoreProvider = Provider<ToplistsCacheStore>(
  (ref) => ToplistsCacheStore(),
);

final toplistsProvider = StateNotifierProvider<ToplistsNotifier, ToplistsState>(
  (ref) => ToplistsNotifier(cache: ref.watch(toplistsCacheStoreProvider)),
);
