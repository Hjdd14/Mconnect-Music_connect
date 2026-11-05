import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/desktop/desktop_sidebar.dart';

/// 1024x600 is the smallest logical window the desktop shell allows (the
/// native minimum size is 1024x600 at 96 DPI). The fixed sidebar column used
/// to overflow by ~130 px there and clipped the settings/account entries
/// behind the player bar; the compact density must keep every entry reachable
/// without a RenderFlex overflow.
void main() {
  testWidgets('sidebar fits a 1024x600 desktop window without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: SizedBox(
              width: 1024,
              height: 600,
              child: DesktopSidebar(
                collapsed: false,
                currentPath: '/settings',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('账号与平台'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
