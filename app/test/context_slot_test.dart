import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stigla/core/context_slot.dart';

void main() {
  group('breakpoint', () {
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

  group('detents', () {
    test('are ordered peek < half < large and large is not fullscreen', () {
      expect(detentFraction(SheetDetent.peek),
          lessThan(detentFraction(SheetDetent.half)));
      expect(detentFraction(SheetDetent.half),
          lessThan(detentFraction(SheetDetent.large)));
      // large leaves a strip of map on top.
      expect(detentFraction(SheetDetent.large), lessThan(1.0));
    });

    test('nearestDetent snaps a drag fraction to the closest stop', () {
      expect(nearestDetent(0.30), SheetDetent.peek);
      expect(nearestDetent(0.45), SheetDetent.half);
      expect(nearestDetent(0.99), SheetDetent.large);
      // A drag between half and large settles by nearest.
      expect(nearestDetent(0.60), SheetDetent.half);
      expect(nearestDetent(0.75), SheetDetent.large);
    });
  });

  group('context view chain', () {
    test('parent walks nearby ← stop ← vehicle', () {
      expect(parentView(ContextView.nearby), isNull);
      expect(parentView(ContextView.stop), ContextView.nearby);
      expect(parentView(ContextView.vehicle), ContextView.stop);
    });
  });

  group('camera view insets (visible-track contract)', () {
    test('desktop keeps the target right of the panel (left inset)', () {
      final insets = contextViewInsets(
        wide: true,
        panelWidth: 384,
        sheetHeight: 0,
      );
      expect(insets, const EdgeInsets.only(left: 384));
    });

    test('mobile keeps the target above the sheet (bottom inset)', () {
      final insets = contextViewInsets(
        wide: false,
        panelWidth: 0,
        sheetHeight: 300,
      );
      expect(insets, const EdgeInsets.only(bottom: 300));
    });

    test('the bottom inset follows the detent height as the sheet is dragged',
        () {
      const available = 800.0;
      final peek = sheetHeightFor(SheetDetent.peek, available);
      final large = sheetHeightFor(SheetDetent.large, available);
      expect(peek, lessThan(large));
      // Dragging peek → large grows the covered area, shrinking the visible
      // strip — the camera compensates by the difference.
      final peekInset =
          contextViewInsets(wide: false, panelWidth: 0, sheetHeight: peek);
      final largeInset =
          contextViewInsets(wide: false, panelWidth: 0, sheetHeight: large);
      expect(largeInset.bottom, greaterThan(peekInset.bottom));
    });
  });
}
