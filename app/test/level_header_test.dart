import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stize/presentation/widgets/level_header.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('first level shows a close control, no back link', (
    tester,
  ) async {
    var closed = 0;
    await tester.pumpWidget(
      _host(
        LevelHeader(title: 'Slavija', onBack: () {}, onClose: () => closed++),
      ),
    );
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    await tester.tap(find.byIcon(Icons.close));
    expect(closed, 1);
  });

  testWidgets('deeper level shows one back link to the previous level', (
    tester,
  ) async {
    var back = 0;
    await tester.pumpWidget(
      _host(
        LevelHeader(
          title: 'Trg republike',
          backLabel: 'Slavija',
          onBack: () => back++,
          onClose: () {},
        ),
      ),
    );
    expect(find.text('Slavija'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    await tester.tap(find.text('Slavija'));
    expect(back, 1);
  });
}
