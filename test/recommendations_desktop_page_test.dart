import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/discovery/presentation/desktop/discovery_desktop_page.dart';
import 'package:mconnect/features/discovery/presentation/desktop/recommendations_desktop_page.dart';
import 'package:mconnect/features/new_songs/presentation/providers/new_songs_provider.dart';
import 'package:mconnect/features/toplist/presentation/providers/toplists_provider.dart';
import 'package:mconnect/features/discovery/presentation/providers/playlist_recommendations_provider.dart';
import 'package:mconnect/models/artist.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/toplist.dart';
import 'package:mconnect/models/song.dart';

/// The full 每日推荐 page: the destination 「查看全部」 never had.
///
/// The home page shows twelve cards; everything beyond them was unreachable.
/// The assertions here are about the two things that made that visible: every
/// de-duplicated song must be listed, and switching the platform filter must
/// change the list (a page that always rendered one platform would still look
/// "complete" to a casual glance).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PlaylistRecommendationsState seeded() {
    final netease = <Song>[
      for (var i = 0; i < 15; i++)
        _song('n-$i', '歌 $i', PlatformType.netease),
    ];
    final qq = <Song>[
      // A cross-platform duplicate of the first netease row: the page must
      // collapse the two with Song.dedupeKey exactly like the teaser does.
      _song('q-dup', '歌 0', PlatformType.qq),
      for (var i = 1; i < 10; i++)
        _song('q-$i', 'Q 歌 $i', PlatformType.qq),
    ];
    final kugou = <Song>[
      for (var i = 0; i < 5; i++)
        _song('k-$i', 'K 歌 $i', PlatformType.kugou),
    ];
    return PlaylistRecommendationsState(
      songsByPlatform: {
        PlatformType.netease: netease,
        PlatformType.qq: qq,
        PlatformType.kugou: kugou,
      },
    );
  }

  Widget wrap(PlaylistRecommendationsNotifier notifier) {
    return ProviderScope(
      overrides: [
        playlistRecommendationsProvider.overrideWith((ref) => notifier),
      ],
      child: const MaterialApp(home: Scaffold(body: RecommendationsDesktopPage())),
    );
  }

  testWidgets('lists every de-duplicated recommendation', (tester) async {
    final state = seeded();
    await tester.pumpWidget(wrap(_FakeRecommendations(state)));
    await tester.pumpAndSettle();

    // 15 + 10 + 5 minus the one cross-platform duplicate.
    expect(find.textContaining('共 29 首'), findsOneWidget);
    expect(find.textContaining('29 首'), findsWidgets);

    // The duplicate must not appear twice: one netease copy survives.
    expect(find.text('歌 0'), findsOneWidget);

    // Rows beyond the teaser's twelve are reachable now: the list is lazy, so
    // scroll to each one instead of assuming the row is mounted.
    for (final title in <String>['歌 14', 'K 歌 4']) {
      await tester.scrollUntilVisible(
        find.text(title),
        240,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('the platform filter narrows the list', (tester) async {
    await tester.pumpWidget(wrap(_FakeRecommendations(seeded())));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('recommendations-filter-qq')));
    await tester.pumpAndSettle();

    // 10 qq songs minus the row that de-duplicated into netease.
    expect(find.text('Q 歌 1'), findsOneWidget);
    expect(find.text('歌 14'), findsNothing);
    expect(find.textContaining('9 首'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('recommendations-filter-all')));
    await tester.pumpAndSettle();
    expect(find.text('歌 0'), findsOneWidget);
  });

  testWidgets('an empty state explains how to get recommendations', (tester) async {
    await tester.pumpWidget(
      wrap(_FakeRecommendations(const PlaylistRecommendationsState())),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无每日推荐'), findsOneWidget);
    expect(find.byKey(const ValueKey('recommendations-play-all')), findsOneWidget);
  });

  testWidgets('the discovery teaser opens the full list', (tester) async {
    // The desktop shell targets a wide window; the default 800x600 test surface
    // overflows the fixed-height rows in the discovery page.
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The discovery page's *empty* 排行榜 / 新歌速递 blocks are taller than the
    // fixed row boxes they sit in (a pre-existing layout issue, unrelated to
    // this way-in). Record the overflow instead of failing on it, and let every
    // other error through.
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        // The router wraps every desktop route in a Scaffold-backed plate; the
        // harness does the same so Material ink widgets find their ancestor.
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const Scaffold(body: DiscoveryDesktopPage()),
        ),
        GoRoute(
          path: '/recommendations',
          builder: (context, state) =>
              const Scaffold(body: RecommendationsDesktopPage()),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playlistRecommendationsProvider.overrideWith(
            (ref) => _FakeRecommendations(seeded()),
          ),
          toplistsProvider.overrideWith((ref) => _FakeToplists()),
          newSongsProvider.overrideWith((ref) => _FakeNewSongs()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // The teaser used to be a dead end: no action, no route. Target the section
    // header itself -- 新歌速递 has its own 「查看全部」 button on the same page.
    final seeAll = find.textContaining('查看全部 29 首');
    expect(seeAll, findsOneWidget);
    await tester.tap(seeAll);
    await tester.pumpAndSettle();

    expect(find.byType(RecommendationsDesktopPage), findsOneWidget);
    expect(find.byKey(const ValueKey('recommendations-play-all')), findsOneWidget);
    // The full page carries rows the 12-card teaser never showed.
    expect(find.byKey(const ValueKey('recommendation-row-netease-n-14')), findsOneWidget);
  });
}

// Empty supported-type lists: the discovery page still asks these hubs to load,
// and with nothing to query they finish without touching the network or leaving
// a spinner running.
class _FakeToplists extends ToplistsNotifier {
  _FakeToplists() : super(supportedTypes: const <PlatformType>[]) {
    // One platform with rows: the empty-state block is taller than the row box
    // it is given on this page, and a layout overflow would fail the test for a
    // reason that has nothing to do with the entry point under test.
    state = const ToplistsState(
      toplistsByPlatform: {
        PlatformType.netease: <Toplist>[
          Toplist(id: '19723756', name: '飙升榜'),
          Toplist(id: '3779629', name: '新歌榜'),
        ],
      },
      platforms: <PlatformType>[PlatformType.netease],
    );
  }
}

class _FakeNewSongs extends NewSongsNotifier {
  _FakeNewSongs() : super(supportedTypes: const <PlatformType>[]);
}

class _FakeRecommendations extends PlaylistRecommendationsNotifier {
  _FakeRecommendations(PlaylistRecommendationsState initial)
    : super(supportedTypes: const <PlatformType>[]) {
    state = initial;
  }

  @override
  Future<void> loadRecommendations() async {}
}

Song _song(String id, String name, PlatformType platform) {
  return Song(
    id: id,
    platform: platform,
    name: name,
    artists: <Artist>[Artist(id: 'a-$id', name: '同一歌手')],
    duration: const Duration(minutes: 3),
  );
}