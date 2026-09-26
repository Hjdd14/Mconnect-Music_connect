import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/theme/ui_style_provider.dart';
import 'package:mconnect/core/widgets/app_bottom_nav_bar.dart';
import 'package:mconnect/core/widgets/floating_glass_nav_bar.dart';
import 'package:mconnect/core/widgets/miuix_bottom_layout.dart';

class _StubUiStyleNotifier extends UiStyleNotifier {
  _StubUiStyleNotifier(UiStyle style) : super(initialStyle: style);

  @override
  Future<void> setStyle(UiStyle style) async {
    state = state.copyWith(style: style);
  }
}

void main() {
  Widget wrap({required UiStyle style, required Widget child}) {
    return ProviderScope(
      overrides: [
        uiStyleProvider.overrideWith(
          (ref) => _StubUiStyleNotifier(style),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  testWidgets('material branch renders the unchanged NavigationBar', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        style: UiStyle.material,
        child: AppBottomNavBar(selectedIndex: 0, onDestinationSelected: (_) {}),
      ),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(AppBottomNavBar.miuixKey), findsNothing);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.explore), findsOneWidget);
    expect(find.byIcon(Icons.library_music), findsOneWidget);
    expect(find.byIcon(Icons.download), findsOneWidget);
    for (final label in const ['搜索', '发现', '音乐库', '下载']) {
      expect(find.text(label), findsOneWidget);
    }

    // Pin the exact destination order/icon/label pairing that the Material
    // branch must keep: it is the pre-existing inline NavigationBar verbatim.
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(
      bar.destinations
          .cast<NavigationDestination>()
          .map((d) => (icon: (d.icon as Icon).icon, label: d.label))
          .toList(),
      const [
        (icon: Icons.search, label: '搜索'),
        (icon: Icons.explore, label: '发现'),
        (icon: Icons.library_music, label: '音乐库'),
        (icon: Icons.download, label: '下载'),
      ],
    );
  });

  testWidgets('miuix branch renders the floating capsule placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        style: UiStyle.miuix,
        child: AppBottomNavBar(selectedIndex: 0, onDestinationSelected: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(AppBottomNavBar.miuixKey), findsOneWidget);
    // 阶段 B keeps the placeholder pure Material: no NavigationBar, no blur.
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    for (final icon in const [
      Icons.search,
      Icons.explore,
      Icons.library_music,
      Icons.download,
    ]) {
      expect(find.byIcon(icon), findsOneWidget);
    }
    for (final label in const ['搜索', '发现', '音乐库', '下载']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('material branch reports the tapped destination index', (
    tester,
  ) async {
    final tapped = <int>[];

    await tester.pumpWidget(
      wrap(
        style: UiStyle.material,
        child: AppBottomNavBar(
          selectedIndex: 0,
          onDestinationSelected: tapped.add,
        ),
      ),
    );

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );

    await tester.tap(find.byIcon(Icons.download));
    await tester.pump();

    expect(tapped, [3]);
  });

  testWidgets('miuix branch reports the tapped destination index', (
    tester,
  ) async {
    final tapped = <int>[];

    await tester.pumpWidget(
      wrap(
        style: UiStyle.miuix,
        child: AppBottomNavBar(
          selectedIndex: 0,
          onDestinationSelected: tapped.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.library_music));
    await tester.pumpAndSettle();

    expect(tapped, [2]);
  });

  testWidgets('floating obstruction height accounts for the capsule', (
    tester,
  ) async {
    late double obstruction;

    await tester.pumpWidget(
      wrap(
        style: UiStyle.miuix,
        child: Builder(
          builder: (context) {
            obstruction = MiuixBottomLayout.navBottomInset(context) +
                MiuixBottomLayout.navCapsuleHeight(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      obstruction,
      FloatingGlassNavBar.bottomMargin + FloatingGlassNavBar.minBarHeight,
    );
  });

  testWidgets('the player inset is the capsule column, not the nav margin', (
    tester,
  ) async {
    late double playerInset;
    late double contentInset;

    await tester.pumpWidget(
      wrap(
        style: UiStyle.miuix,
        child: Builder(
          builder: (context) {
            playerInset = MiuixBottomLayout.playerBottomInset(context);
            contentInset = MiuixBottomLayout.contentInset(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // The player sits on top of the nav capsule, so its inset is the nav margin
    // plus the capsule plus the gap -- never the decorative margin alone, which
    // would let the nav capsule cover the player's content (the reported defect).
    expect(
      playerInset,
      FloatingGlassNavBar.bottomMargin +
          FloatingGlassNavBar.minBarHeight +
          MiuixBottomLayout.playerGap,
    );
    expect(
      contentInset,
      playerInset + MiuixBottomLayout.playerHeight,
      reason: 'page content must clear the player capsule entirely',
    );
    expect(playerInset, greaterThan(FloatingGlassNavBar.bottomMargin));
  });
}
