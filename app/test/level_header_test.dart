import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stize/presentation/widgets/level_header.dart';
import 'package:stize/core/design/stize_icons.dart';

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
    expect(find.byIcon(StizeIcons.close), findsOneWidget);
    expect(find.byIcon(StizeIcons.back), findsNothing);
    await tester.tap(find.byIcon(StizeIcons.close));
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
    expect(find.byIcon(StizeIcons.close), findsNothing);
    await tester.tap(find.text('Slavija'));
    expect(back, 1);
  });
}
