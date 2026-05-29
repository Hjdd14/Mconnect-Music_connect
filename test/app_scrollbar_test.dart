import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mconnect/core/widgets/app_scrollbar.dart';

void main() {
  testWidgets(
    'AppScrollbar wires an interactive scrollbar to the child scrollable',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: AppScrollbar(
                builder: (controller) => ListView.builder(
                  controller: controller,
                  itemExtent: 48,
                  itemCount: 30,
                  itemBuilder: (context, index) => Text('Item $index'),
                ),
              ),
            ),
          ),
        ),
      );

      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(scrollbar.interactive, isTrue);
      expect(scrollbar.thumbVisibility, isTrue);
      expect(scrollbar.controller, isNotNull);
      expect(find.text('Item 0'), findsOneWidget);
    },
  );
}
