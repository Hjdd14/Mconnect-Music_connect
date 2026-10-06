import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/network/platform_http.dart';
import '../../../../models/platform_type.dart';
import '../../../../models/song.dart';
import '../../../../platform/base/music_platform.dart';
import '../../../../platform/base/platform_registry.dart';

/// Region chips, in display order, with the Chinese labels the page shows.
const Map<NewSongRegion, String> newSongRegionLabels = {
  NewSongRegion.all: '全部',
  NewSongRegion.chinese: '华语',
  NewSongRegion.western: '欧美',
  NewSongRegion.japanese: '日本',
  NewSongRegion.korean: '韩国',
  NewSongRegion.hongKongTaiwan: '港台',
};

/// New releases, grouped by platform.
///
/// The three platforms cannot make the same promise here, and the page must not
/// paper over that with a blank list:
/// * 网易云 has no 港台 new-song region at all (verified: `areaId` 6/14/60 all
///   return an empty `data`), so its adapter throws
///   [UnsupportedActionException] and the page states it;
/// * 酷狗 does not implement the feature (`supportsNewSongs == false`), so it is
///   never called and says so;
/// * QQ answers for every region and ignores `limit`, so the adapter truncates.
class NewSongsState {
  final NewSongRegion region;
  final Map<PlatformType, List<Song>> songsByPlatform;

  /// Platform-level explanations: capability missing, or the selected region is
  /// not offered by that platform. Rendered instead of an empty list.
  final Map<PlatformType, String> noticesByPlatform;

  /// Real failures (network / server), shown with a retry affordance.
  final Map<PlatformType, String> errorsByPlatform;

  final bool isLoading;

  const NewSongsState({
    this.region = NewSongRegion.all,
    this.songsByPlatform = const {},
    this.noticesByPlatform = const {},
    this.errorsByPlatform = const {},
    this.isLoading = false,
  });

  NewSongsState copyWith({
    NewSongRegion? region,
    Map<PlatformType, List<Song>>? songsByPlatform,
    Map<PlatformType, String>? noticesByPlatform,
    Map<PlatformType, String>? errorsByPlatform,
    bool? isLoading,
  }) {
    return NewSongsState(
      region: region ?? this.region,
      songsByPlatform: songsByPlatform ?? this.songsByPlatform,
      noticesByPlatform: noticesByPlatform ?? this.noticesByPlatform,
      errorsByPlatform: errorsByPlatform ?? this.errorsByPlatform,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  List<Song> songsForPlatform(PlatformType platform) =>
      songsByPlatform[platform] ?? const [];

  String? noticeForPlatform(PlatformType platform) =>
      noticesByPlatform[platform];

  String? errorForPlatform(PlatformType platform) => errorsByPlatform[platform];

  bool get hasAnyData => songsByPlatform.values.any((list) => list.isNotEmpty);

  int get totalCount =>
      songsByPlatform.values.fold(0, (sum, list) => sum + list.length);
}

class NewSongsNotifier extends StateNotifier<NewSongsState> {
  final List<PlatformType> Function() _supportedTypes;
  final MusicPlatform Function(PlatformType) _platformResolver;
  final Duration operationTimeout;

  NewSongsNotifier({
    List<PlatformType>? supportedTypes,
    MusicPlatform Function(PlatformType)? platformResolver,
    this.operationTimeout = const Duration(seconds: 15),
  }) : _supportedTypes = (() =>
           supportedTypes ?? PlatformRegistry.supportedTypes),
       _platformResolver = platformResolver ?? PlatformRegistry.get,
       super(const NewSongsState());

  Future<void> load({NewSongRegion? region}) async {
    final target = region ?? state.region;
    state = state.copyWith(
      region: target,
      isLoading: true,
      noticesByPlatform: const {},
      errorsByPlatform: const {},
    );

    final implementations = _implementations();

    final loaded = await Future.wait(
      implementations.map((impl) => _loadPlatform(impl, target)),
    );
    if (!mounted) return;

    final songs = <PlatformType, List<Song>>{};
    final notices = <PlatformType, String>{};
    final errors = <PlatformType, String>{};
    for (final item in loaded) {
      if (item.songs.isNotEmpty) songs[item.platform] = item.songs;
      if (item.notice != null) notices[item.platform] = item.notice!;
      if (item.error != null) errors[item.platform] = item.error!;
    }

    state = state.copyWith(
      region: target,
      songsByPlatform: songs,
      noticesByPlatform: notices,
      errorsByPlatform: errors,
      isLoading: false,
    );
  }

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

  Future<_PlatformNewSongs> _loadPlatform(
    MusicPlatform impl,
    NewSongRegion region,
  ) async {
    final platform = impl.platformType;

    if (!impl.supportsNewSongs) {
      return _PlatformNewSongs(
        platform: platform,
        notice: '${platform.displayName}暂不支持新歌速递',
      );
    }

    try {
      final songs = await impl
          .getNewSongs(limit: 100, region: region)
          .timeout(operationTimeout);
      if (songs.isNotEmpty) {
        return _PlatformNewSongs(platform: platform, songs: songs);
      }
      return _PlatformNewSongs(
        platform: platform,
        notice: region == NewSongRegion.all
            ? '暂无新歌数据'
            : '${newSongRegionLabels[region]}地区暂无新歌',
      );
    } on UnsupportedActionException catch (e) {
      final details = e.details;
      return _PlatformNewSongs(
        platform: platform,
        notice: details == null || details.isEmpty
            ? e.message
            : '${e.message}（$details）',
      );
    } catch (e) {
      return _PlatformNewSongs(
        platform: platform,
        error: apiExceptionOf(e).message,
      );
    }
  }
}

class _PlatformNewSongs {
  final PlatformType platform;
  final List<Song> songs;
  final String? notice;
  final String? error;

  const _PlatformNewSongs({
    required this.platform,
    this.songs = const [],
    this.notice,
    this.error,
  });
}

final newSongsProvider =
    StateNotifierProvider<NewSongsNotifier, NewSongsState>((ref) {
      return NewSongsNotifier();
    });
