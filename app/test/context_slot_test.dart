import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/context_slot.dart';

void main() {
  group('map geometry owner (single source of camera padding)', () {
    test('desktop → left inset clears the island (margin + panel width)', () {
      expect(
        mapInsetsFor(panelActive: true, panelWidth: 384, mobileSheetPx: 300),
        const EdgeInsets.only(left: kPanelIslandInset + 384),
      );
    });

    test('mobile → bottom inset is the sheet height', () {
      expect(
        mapInsetsFor(panelActive: false, panelWidth: 384, mobileSheetPx: 260),
        const EdgeInsets.only(bottom: 260),
      );
    });

    test('mobile with no sheet → zero (free browse, no phantom inset)', () {
      expect(
        mapInsetsFor(panelActive: false, panelWidth: 384, mobileSheetPx: 0),
        EdgeInsets.zero,
      );
    });

    test('collapsed desktop panel → zero left inset (view hidden, A#3)', () {
      expect(
        mapInsetsFor(
          panelActive: true,
          panelWidth: 384,
          mobileSheetPx: 0,
          panelCollapsed: true,
        ),
        EdgeInsets.zero,
      );
    });

    test('collapse flag is ignored on mobile (no panel to hide)', () {
      expect(
        mapInsetsFor(
          panelActive: false,
          panelWidth: 384,
          mobileSheetPx: 260,
          panelCollapsed: true,
        ),
        const EdgeInsets.only(bottom: 260),
      );
    });

    test('crossing desktop→mobile drops the left inset (R3 #2 resize drift)', () {
      final desktop =
          mapInsetsFor(panelActive: true, panelWidth: 384, mobileSheetPx: 0);
      final mobile =
          mapInsetsFor(panelActive: false, panelWidth: 384, mobileSheetPx: 0);
      expect(desktop.left, kPanelIslandInset + 384);
      expect(mobile.left, 0); // the panel padding is gone on mobile
    });
  });

  group('mobile sheet detents (large is not fullscreen)', () {
    test('ordered peek < half < large, large leaves a map strip', () {
      expect(kSheetPeek, lessThan(kSheetHalf));
      expect(kSheetHalf, lessThan(kSheetLarge));
      expect(kSheetLarge, lessThan(1.0)); // a strip of map always stays on top
      expect(kSheetDetents, [kSheetPeek, kSheetHalf, kSheetLarge]);
    });
  });

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

  group('panel width (rubber-band: min 360 / ~28% / max 400)', () {
    test('clamps to the floor at narrow desktop widths', () {
      // 28% of 840 = 235 → floored to 360.
      expect(panelWidthFor(840), 360);
      expect(panelWidthFor(1000), 360);
    });

    test('follows 28% in the middle of the band', () {
      expect(panelWidthFor(1400), closeTo(392, 0.01));
    });

    test('caps at the ceiling for wide windows', () {
      // 28% of 2000 = 560 → capped to 400.
      expect(panelWidthFor(2000), 400);
    });
  });
}
