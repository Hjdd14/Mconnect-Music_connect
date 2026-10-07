import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/discovery/presentation/providers/playlist_recommendations_provider.dart';
import 'package:mconnect/features/discovery/presentation/screens/discovery_screen.dart';
import 'package:mconnect/features/library/presentation/screens/library_screen.dart';

/// 榜单中心 / 新歌速递 live on the 发现 tab only.
///
/// Both halves of that statement are guarded, because either one alone is a bug:
/// * re-adding the library copy makes the library list long enough to push 设置
///   below the fold on a compact screen, for two destinations that were already
///   one tab away;
/// * dropping the discovery entry without the library one would make
///   `/toplists` and `/new-songs` unreachable entirely.
///
/// The library assertion deliberately inspects the ListView's **declared**
/// children rather than the laid-out ones. `ListView` only builds what is near
/// the viewport, so a `find.text(...)` / `findsNothing` pair would pass on the
/// old code too (the removed rows sat low enough to be off-screen) - a test with
/// no teeth. `SliverChildListDelegate.children` holds every child as a widget
/// regardless of scrolling, which is what makes the negative assertion real.
void main() {
  List<String?> libraryEntryTitles(WidgetTester tester) {
    final listView = tester.widget<ListView>(find.byType(ListView));
    // Throws if the page stops using ListView(children: ...): a loud failure is
    // better than silently asserting over an empty list.
    final delegate = listView.childrenDelegate as SliverChildListDelegate;
    return delegate.children
        .whereType<ListTile>()
        .map((tile) => (tile.title as Text?)?.data)
        .toList();
  }

  group('library vs discovery entries', () {
    testWidgets('the library screen no longer lists them', (tester) async {
      // A Scaffold supplies the Material ancestor ListTile requires; the real app
      // gets it from the route shell.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LibraryScreen())),
      );

      final titles = libraryEntryTitles(tester);

      expect(
        titles,
        isNot(contains('榜单中心')),
        reason: 'the chart hub belongs to the 发现 tab',
      );
      expect(
        titles,
        isNot(contains('新歌速递')),
        reason: 'new releases belong to the 发现 tab',
      );

      // The library's own destinations - including the last one, which proves
      // the whole declaration list was inspected - are untouched.
      expect(
        titles,
        containsAll(<String>[
          '我喜欢的音乐',
          '听歌历史',
          '听歌统计',
          '本地音乐',
          '离线缓存',
          '智能歌单',
          '歌单',
          '导入歌单',
          '下载管理',
          '设置',
        ]),
      );
    });

    testWidgets('the discovery screen still lists both', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // An empty platform list means loadRecommendations() iterates over
            // nothing: the pump touches no network, no database and no platform,
            // while the entries the screen renders itself are unaffected.
            playlistRecommendationsProvider.overrideWith(
              (ref) => PlaylistRecommendationsNotifier(supportedTypes: const []),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: DiscoveryScreen())),
        ),
      );
      await tester.pump();

      // Both entries sit in the first screenful, so they are built; this is the
      // "the content is still reachable" half of the guard.
      expect(find.text('榜单中心'), findsWidgets);
      expect(find.text('新歌速递'), findsOneWidget);
    });
  });
}
