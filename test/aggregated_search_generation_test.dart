import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/search/presentation/providers/aggregated_search_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/song.dart';
import 'package:mconnect/platform/base/music_platform.dart';

/// `search()` had no generation guard (only `loadMore` had an `isLoading` one):
/// typing "晴" and then "晴天" quickly let the slower first response publish over
/// the newer query's results.
class _GatedSearchPlatform extends MusicPlatform {
  _GatedSearchPlatform(this.type);

  final PlatformType type;

  /// Keyed `query|page`; the test decides when each call answers.
  final pending = <String, Completer<List<Song>>>{};

  @override
  PlatformType get platformType => type;

  @override
  String get platformName => type.displayName;

  @override
  bool get isLoggedIn => false;

  @override
  Future<List<Song>> search(String keyword, {int page = 1, int limit = 30}) {
    final completer = Completer<List<Song>>();
    pending['$keyword|$page'] = completer;
    return completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Song _song(String id, String name) => Song(
  id: id,
  platform: PlatformType.netease,
  name: name,
  artists: const [Artist(id: 'a', name: '歌手')],
);

void main() {
  test('慢的旧查询回答时不会覆盖新查询的结果', () async {
    final platform = _GatedSearchPlatform(PlatformType.netease);
    final notifier = AggregatedSearchNotifier(
      supportedTypes: const [PlatformType.netease],
      platformResolver: (_) => platform,
    );
    addTearDown(notifier.dispose);

    // Two searches in flight; the first one is slower.
    final slow = notifier.search('晴');
    final fast = notifier.search('晴天');

    platform.pending['晴天|1']!.complete([_song('new', '晴天')]);
    await fast;
    expect(notifier.state.query, '晴天');
    expect(
      notifier.state.songs.map((s) => s.sources.single.name).toList(),
      ['晴天'],
    );

    // The stale page-1 response arrives last and must be dropped.
    platform.pending['晴|1']!.complete([_song('old', '晴天旧结果')]);
    await slow;

    expect(
      notifier.state.query,
      '晴天',
      reason: '旧查询的结果不得把状态改回旧查询',
    );
    expect(
      notifier.state.songs.map((s) => s.sources.single.name).toList(),
      ['晴天'],
      reason: '旧响应必须被代际守卫丢弃',
    );
    expect(notifier.state.isLoading, isFalse);
  });

  test('清空后，仍在飞行中的查询不会复活状态', () async {
    final platform = _GatedSearchPlatform(PlatformType.netease);
    final notifier = AggregatedSearchNotifier(
      supportedTypes: const [PlatformType.netease],
      platformResolver: (_) => platform,
    );
    addTearDown(notifier.dispose);

    final inFlight = notifier.search('晴天');
    notifier.clear();

    platform.pending['晴天|1']!.complete([_song('new', '晴天')]);
    await inFlight;

    expect(notifier.state.query, isEmpty);
    expect(notifier.state.songs, isEmpty);
  });
}
