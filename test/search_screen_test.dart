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
}
