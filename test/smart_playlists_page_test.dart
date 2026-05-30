import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/features/smart_playlists/data/smart_playlist_repository.dart';
import 'package:mconnect/features/smart_playlists/presentation/pages/smart_playlists_page.dart';
import 'package:mconnect/features/smart_playlists/presentation/providers/smart_playlists_provider.dart';

void main() {
  testWidgets('smart playlists page exposes rule list and create action', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smartPlaylistsProvider.overrideWith(
            (ref) => SmartPlaylistsNotifier(
              repository: MemorySmartPlaylistRepository(),
            ),
          ),
        ],
        child: const MaterialApp(home: SmartPlaylistsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('智能歌单'), findsOneWidget);
    expect(find.text('暂无智能歌单'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
