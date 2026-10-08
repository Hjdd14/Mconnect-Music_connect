import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/search/presentation/screens/search_screen.dart';
import 'package:mconnect/models/platform_type.dart';
import 'package:mconnect/models/playlist.dart';

import 'support/content_page_fakes.dart';

void main() {
  Widget wrap(Widget child, {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(SearchScreen)));

  testWidgets('search screen lets users switch between songs and playlists', (tester) async {
    await tester.pumpWidget(wrap(const SearchScreen()));
    final container = containerOf(tester);

    expect(find.text('歌曲'), findsOneWidget);
    expect(find.text('歌单'), findsOneWidget);

    await tester.tap(find.text('歌单'));
    await tester.pump();

    expect(container.read(searchModeProvider), SearchMode.playlists);
  });

  testWidgets('search input updates query after debounce and clears immediately', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const SearchScreen()));
    final container = containerOf(tester);

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.pump(const Duration(milliseconds: 299));
    expect(container.read(searchQueryProvider), isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    expect(container.read(searchQueryProvider), '周杰伦');

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    expect(container.read(searchQueryProvider), isEmpty);
  });

  testWidgets('search distinguishes initial empty state from no results', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const SearchScreen(),
        overrides: [
          searchResultsProvider.overrideWith((ref) async => const []),
        ],
      ),
    );
    final container = containerOf(tester);
    await tester.pump();

    expect(find.text('请输入关键词'), findsOneWidget);

    container.read(searchQueryProvider.notifier).state = 'no-match';
    await tester.pump();
    await tester.pump();

    expect(find.text('未找到相关内容'), findsOneWidget);

    // Both of these are *empty* states, not failures, so neither may offer a
    // retry. The hand-rolled versions were bare `Text`s; the migration onto
    // `AsyncStateView.empty` is what makes "no retry" a contract guarantee
    // rather than an accident.
    expect(find.text('重试'), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('a failed search is an error state whose retry is an ElevatedButton', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const SearchScreen(),
        overrides: [
          searchResultsProvider.overrideWith(
            (ref) async => throw Exception('search down'),
          ),
        ],
      ),
    );
    final container = containerOf(tester);

    container.read(searchQueryProvider.notifier).state = 'x';
    await tester.pump();
    await tester.pump();

    // The message is the one `apiExceptionOf` normalises the raw exception into,
    // so the page never shows an untranslated `Exception.toString()` of its own
    // construction.
    expect(find.textContaining('search down'), findsOneWidget);
    // Contract rule 1: retry is an `ElevatedButton`, and it is the only button
    // on screen in this state.
    expect(find.widgetWithText(ElevatedButton, '重试'), findsOneWidget);
  });

  group('收藏歌单 goes through snackbar_helper', () {
    Future<void> pumpPlaylistResults(
      WidgetTester tester,
      bool collectResult,
    ) async {
      registerFake(_CollectingPlatform(collectResult));
      await tester.pumpWidget(
        wrap(
          const SearchScreen(),
          overrides: [
            playlistSearchResultsProvider.overrideWith(
              (ref) async => const [
                Playlist(id: 'p1', name: '我的歌单', platform: PlatformType.qq),
              ],
            ),
          ],
        ),
      );
      final container = containerOf(tester);
      container.read(searchModeProvider.notifier).state = SearchMode.playlists;
      container.read(searchQueryProvider.notifier).state = 'q';
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a successful collect shows a floating, non-error SnackBar', (
      tester,
    ) async {
      await pumpPlaylistResults(tester, true);

      await tester.tap(find.byIcon(Icons.bookmark_border));
      await tester.pump();
      await tester.pump();

      expect(find.text('已收藏歌单'), findsOneWidget);

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      // Changed by W0-F: the bare `SnackBar` this replaced was not `floating`,
      // so the bottom navigation capsule and the mini player covered it.
      expect(snackBar.behavior, SnackBarBehavior.floating);
      // ...and success carried no colour of its own.
      expect(snackBar.backgroundColor, isNull);
    });

    testWidgets('a failed collect is painted with the theme error colour', (
      tester,
    ) async {
      await pumpPlaylistResults(tester, false);

      await tester.tap(find.byIcon(Icons.bookmark_border));
      await tester.pump();
      await tester.pump();

      expect(find.text('收藏失败'), findsOneWidget);

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      final scheme = Theme.of(
        tester.element(find.byType(SnackBar)),
      ).colorScheme;

      expect(snackBar.behavior, SnackBarBehavior.floating);
      // The real regression: the old bare SnackBar painted success and failure
      // identically, so "收藏失败" read like "已收藏歌单".
      expect(snackBar.backgroundColor, scheme.error);
    });
  });
}

/// A platform whose `collectPlaylist` answers whatever the test needs.
class _CollectingPlatform extends FakeContentPlatform {
  _CollectingPlatform(this.result) : super(type: PlatformType.qq);

  final bool result;

  @override
  Future<bool> collectPlaylist(String playlistId, {bool collect = true}) async =>
      result;
}
