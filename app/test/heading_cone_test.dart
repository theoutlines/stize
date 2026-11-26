import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/design/stize_theme.dart';
import 'package:stize/core/map_support.dart';

Widget _host(double? heading) => MaterialApp(
  theme: StizeTheme.dark(),
  home: Center(child: MeLocationDot(heading: heading)),
);

int _cones(WidgetTester t) => find
    .descendant(
      of: find.byType(MeLocationDot),
      matching: find.byType(AnimatedRotation),
    )
    .evaluate()
    .length;

void main() {
  test('turns by the shortest way across north', () {
    expect(headingDelta(350, 10), 20);
    expect(headingDelta(10, 350), -20);
    expect(headingDelta(90, 270), 180);
    expect(headingDelta(0, 0), 0);
  });

  testWidgets('no compass, no cone: the dot alone', (tester) async {
    await tester.pumpWidget(_host(null));
    expect(_cones(tester), 0);
  });

  testWidgets('a heading draws the cone, and it never blocks the map', (
    tester,
  ) async {
    await tester.pumpWidget(_host(120));
    expect(_cones(tester), 1);
    expect(
      find.descendant(
        of: find.byType(MeLocationDot),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );
  });

  testWidgets('350 to 10 turns forward 20 degrees, not back 340', (
    tester,
  ) async {
    await tester.pumpWidget(_host(350));
    await tester.pumpWidget(_host(10));
    final rot = tester.widget<AnimatedRotation>(find.byType(AnimatedRotation));
    expect(rot.turns, closeTo(370 / 360, 1e-9));
  });
}
