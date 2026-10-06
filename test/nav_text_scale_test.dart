import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/theme/ui_style_provider.dart';
import 'package:mconnect/core/widgets/app_bottom_nav_bar.dart';

/// The bottom navigation is one of the three surfaces migrated to ARB lookups in
/// this workflow, so its labels have to survive the two things that page has to
/// survive as well: a locale change and a 200 % font scale.
class _StubUiStyleNotifier extends UiStyleNotifier {
  _StubUiStyleNotifier(UiStyle style) : super(initialStyle: style);

  @override
  Future<void> setStyle(UiStyle style) async {
    state = state.copyWith(style: style);
  }
}

void main() {
  Widget wrap({
    required UiStyle style,
    required Widget child,
    double textScale = 1.0,
    Locale? locale,
  }) {
    return ProviderScope(
      overrides: [
        uiStyleProvider.overrideWith((ref) => _StubUiStyleNotifier(style)),
      ],
      child: MaterialApp(
        locale: locale,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: child),
        ),
      ),
    );
  }

  for (final style in UiStyle.values) {
    testWidgets('$style bottom bar renders its four labels at 200 % text scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          style: style,
          textScale: 2.0,
          child: AppBottomNavBar(selectedIndex: 0, onDestinationSelected: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final label in const ['搜索', '发现', '音乐库', '下载']) {
        expect(find.text(label), findsWidgets, reason: 'missing $label ($style)');
      }
    });
  }

  testWidgets('the four labels come from the ARB, not from a hard-coded list', (
    tester,
  ) async {
    // Locale switch is the proof: with the English bundle selected the very same
    // widget renders English labels. (The app declares only `zh` today; see
    // `appSupportedLocales`.)
    await tester.pumpWidget(
      wrap(
        style: UiStyle.material,
        locale: const Locale('zh'),
        child: AppBottomNavBar(selectedIndex: 0, onDestinationSelected: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('音乐库'), findsWidgets);
    expect(find.text('Library'), findsNothing);
  });
}
