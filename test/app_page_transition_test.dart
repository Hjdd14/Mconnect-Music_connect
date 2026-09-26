import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/motion/app_motion.dart';
import 'package:mconnect/core/motion/app_page_transition.dart';

/// The transition must keep the incoming page **fully opaque**.
///
/// That is not a cosmetic detail. The route backing's opacity is what the user
/// sees over their background image, and it has to stay low enough to read as
/// "my background is showing" — most visibly on the home screen. If the transition
/// also relied on that backing to hide the outgoing page, the two requirements
/// would fight, and lowering the backing would bring the ghosting back.
///
/// So the masking is structural (an opaque incoming page) and these tests pin it.
void main() {
  Future<void> pumpTransition(
    WidgetTester tester, {
    required double animationValue,
    required double secondaryValue,
    bool reduceMotion = false,
  }) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: buildAppPageTransition(
          animation: AlwaysStoppedAnimation<double>(animationValue),
          secondaryAnimation: AlwaysStoppedAnimation<double>(secondaryValue),
          reduceMotion: reduceMotion,
          child: const SizedBox.shrink(),
        ),
      ),
    );
  }

  SlideTransition incomingSlide(WidgetTester tester) =>
      tester.widget<SlideTransition>(find.byType(SlideTransition));

  void expectOffset(Offset actual, Offset expected) {
    expect(actual.dx, closeTo(expected.dx, 1e-9));
    expect(actual.dy, closeTo(expected.dy, 1e-9));
  }

  testWidgets('the incoming page never fades: no opacity is applied at all', (
    tester,
  ) async {
    // A `FadeTransition` here would let the page below show through for most of
    // the animation (at 0.5 both pages are half-visible), which is exactly the
    // ghosting that was reported three separate times.
    await pumpTransition(tester, animationValue: 0.5, secondaryValue: 0);
    expect(find.byType(FadeTransition), findsNothing);

    await pumpTransition(tester, animationValue: 0, secondaryValue: 0);
    expect(find.byType(FadeTransition), findsNothing);

    await pumpTransition(tester, animationValue: 1, secondaryValue: 0);
    expect(find.byType(FadeTransition), findsNothing);
  });

  testWidgets('the covered page is left completely alone', (tester) async {
    // No fade, no scale and no shift on the page below: it must not move, so the
    // only thing changing on screen is the incoming page sliding over it.
    await pumpTransition(tester, animationValue: 0.5, secondaryValue: 1);
    expect(find.byType(ScaleTransition), findsNothing);
    expect(find.byType(SlideTransition), findsOneWidget);
    expect(find.byType(Opacity), findsNothing);

    // The single slide belongs to the incoming page, so at rest it is exactly at
    // the origin regardless of how far the secondary animation has run.
    await pumpTransition(tester, animationValue: 1, secondaryValue: 1);
    expectOffset(incomingSlide(tester).position.value, Offset.zero);
  });

  testWidgets('incoming page starts offset to the right and settles at rest', (
    tester,
  ) async {
    await pumpTransition(tester, animationValue: 0, secondaryValue: 0);
    expectOffset(
      incomingSlide(tester).position.value,
      const Offset(AppMotion.incomingSlide, 0),
    );

    await pumpTransition(tester, animationValue: 1, secondaryValue: 0);
    expectOffset(incomingSlide(tester).position.value, Offset.zero);
  });

  testWidgets('reduced motion shows the page immediately, still opaque', (
    tester,
  ) async {
    await pumpTransition(
      tester,
      animationValue: 0.5,
      secondaryValue: 1,
      reduceMotion: true,
    );

    // No slide, and crucially no fade-in: fading from 0 would re-introduce the
    // ghosting for users who ask for reduced motion.
    expect(find.byType(SlideTransition), findsNothing);
    expect(find.byType(FadeTransition), findsNothing);
    expect(find.byType(ScaleTransition), findsNothing);
  });

  test('route timings stay locked to the values existing tests assert', () {
    // Mirrors test/widget_test.dart lines 364-367; both places must agree.
    expect(AppMotion.routeForward, const Duration(milliseconds: 280));
    expect(AppMotion.routeReverse, const Duration(milliseconds: 220));
  });
}
