import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/desktop/desktop_media_card.dart';

/// Regression: the hover lift must stay inside the card's own layout box.
///
/// The discovery rows and the library grid put these cards inside clipped
/// scroll viewports (a horizontal `ListView` with a fixed height, a
/// `GridView`). When the lift was a bare upward translation the viewport cut
/// the top three pixels of the cover, so a hovered cover lost its top strip --
/// exactly the defect the user reported. The card now reserves the lift as
/// padding and moves the cover back to zero, which keeps every rect inside the
/// card no matter who clips it.
void main() {
  Widget harness({double height = 260}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 640,
            height: height,
            // The clip is the point: ListView clips its viewport by default.
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: const [
                DesktopMediaCard(
                  title: '一首歌',
                  subtitle: '歌手',
                  width: 164,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<TestGesture> hover(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(DesktopMediaCard)));
    await tester.pumpAndSettle();
    return gesture;
  }

  Rect coverRect(WidgetTester tester) =>
      tester.getRect(find.byType(ClipRRect).first);

  testWidgets('the hover lift keeps the cover inside the card', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final cardBefore = tester.getRect(find.byType(DesktopMediaCard));
    final coverBefore = coverRect(tester);

    // At rest the cover already sits exactly one lift below the card's top
    // edge: that reserved band is what the hover animation spends.
    expect(coverBefore.top, closeTo(cardBefore.top + DesktopMediaCard.hoverLift, 0.01));
    expect(coverBefore.height, cardBefore.width);

    final titleBefore = tester.getTopLeft(find.text('一首歌'));

    await hover(tester);

    final cardAfter = tester.getRect(find.byType(DesktopMediaCard));
    final coverAfter = coverRect(tester);

    // The lift never pokes out of the card, so a clipped ancestor cannot cut
    // it and the cover keeps its full height.
    expect(coverAfter.top, greaterThanOrEqualTo(cardAfter.top - 0.01));
    expect(coverAfter.height, closeTo(coverBefore.height, 0.01));
    expect(coverAfter.width, closeTo(coverBefore.width, 0.01));

    // The hovered cover rises to exactly the card's top edge.
    expect(coverAfter.top, closeTo(cardAfter.top, 0.01));

    // Lifting must not reflow the text under the cover.
    expect(tester.getTopLeft(find.text('一首歌')), titleBefore);
  });

  testWidgets('the lifted cover stays visible inside a clipped viewport', (
    tester,
  ) async {
    // A viewport exactly as tall as the card: any outward translation would
    // be clipped here, which is the reported failure mode.
    await tester.pumpWidget(harness(height: 250));
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byType(ListView).first);

    await hover(tester);

    final cover = coverRect(tester);
    expect(cover.top, greaterThanOrEqualTo(viewport.top - 0.01));
    expect(cover.bottom, lessThanOrEqualTo(viewport.bottom + 0.01));
  });
}
