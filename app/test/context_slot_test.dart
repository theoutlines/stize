import 'package:flutter_test/flutter_test.dart';
import 'package:stigla/core/context_slot.dart';

void main() {
  group('breakpoint (panel is desktop-only)', () {
    test('840 is the desktop cutoff; below is mobile (portrait tablet = mobile)',
        () {
      expect(isWideLayout(839.9), isFalse);
      expect(isWideLayout(840.0), isTrue);
      expect(isWideLayout(1440), isTrue);
      // A portrait tablet (e.g. iPad 810 logical px) is mobile layout.
      expect(isWideLayout(810), isFalse);
    });
  });

  group('panel width (rubber-band: min 360 / ~28% / max 440)', () {
    test('clamps to the floor at narrow desktop widths', () {
      // 28% of 840 = 235 → floored to 360.
      expect(panelWidthFor(840), 360);
      expect(panelWidthFor(1000), 360);
    });

    test('follows 28% in the middle of the band', () {
      expect(panelWidthFor(1400), closeTo(392, 0.01));
    });

    test('caps at the ceiling for wide windows', () {
      // 28% of 2000 = 560 → capped to 440.
      expect(panelWidthFor(2000), 440);
    });
  });
}
