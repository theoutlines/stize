import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stize/core/design/stize_theme.dart';
import 'package:stize/presentation/widgets/stretch_card_list.dart';

// A trackpad on the web scrolls by pointer signals, which Flutter clamps at
// the ends; the list rubber-bands them itself (owner, 2026-11-26).
void main() {
  testWidgets('a wheel push at the top stretches past it and springs back', (
    tester,
  ) async {
    final ctl = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        theme: StizeTheme.dark(),
        home: Scaffold(
          body: StretchCardList(
            controller: ctl,
            children: [
              for (var i = 0; i < 30; i++)
                SizedBox(height: 60, child: Text('$i')),
            ],
          ),
        ),
      ),
    );
    final at = tester.getCenter(find.byType(StretchCardList));
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    pointer.hover(at);
    for (var i = 0; i < 5; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -20)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(ctl.offset, lessThan(-5));
    await tester.pumpAndSettle();
    expect(ctl.offset, 0);
  });
}
