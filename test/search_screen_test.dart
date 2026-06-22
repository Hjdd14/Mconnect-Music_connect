import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/search/presentation/screens/search_screen.dart';

void main() {
  testWidgets('search screen lets users switch between songs and playlists', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SearchScreen())),
      ),
    );
    final context = tester.element(find.byType(SearchScreen));
    final container = ProviderScope.containerOf(context);

    expect(find.text('歌曲'), findsOneWidget);
    expect(find.text('歌单'), findsOneWidget);

    await tester.tap(find.text('歌单'));
    await tester.pump();

    expect(container.read(searchModeProvider), SearchMode.playlists);
  });

  testWidgets('search input updates query after debounce and clears immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SearchScreen())),
      ),
    );
    final context = tester.element(find.byType(SearchScreen));
    final container = ProviderScope.containerOf(context);

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
      ProviderScope(
        overrides: [
          searchResultsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: Scaffold(body: SearchScreen())),
      ),
    );
    final context = tester.element(find.byType(SearchScreen));
    final container = ProviderScope.containerOf(context);
    await tester.pump();

    expect(find.text('请输入关键词'), findsOneWidget);

    container.read(searchQueryProvider.notifier).state = 'no-match';
    await tester.pump();
    await tester.pump();

    expect(find.text('未找到相关内容'), findsOneWidget);
  });
}
