import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/arrival_display.dart';
import 'package:stize/core/live_position.dart';
import 'package:stize/domain/models/arrival.dart';

ArrivalsBoard _load(String name) => ArrivalsBoard.fromJson(
      jsonDecode(File('test/fixtures/$name.json').readAsStringSync())
          as Map<String, dynamic>,
    );

void main() {
  group('arrivalProximity — trust stops_remaining only when it agrees with ETA', () {
    test('0 stops + a near ETA is "here"', () {
      expect(arrivalProximity(stopsRemaining: 0, etaMinutes: 0), ArrivalProximity.here);
      expect(arrivalProximity(stopsRemaining: 0, etaMinutes: 2), ArrivalProximity.here);
    });

    test('0 stops + a far ETA is junk → unknown (never "here")', () {
      expect(arrivalProximity(stopsRemaining: 0, etaMinutes: 7), ArrivalProximity.unknown);
      expect(arrivalProximity(stopsRemaining: 0, etaMinutes: 19), ArrivalProximity.unknown);
    });

    test('a positive count is trusted', () {
      expect(arrivalProximity(stopsRemaining: 5, etaMinutes: 15), ArrivalProximity.stopsAway);
    });

    test('null/negative is unknown', () {
      expect(arrivalProximity(stopsRemaining: null, etaMinutes: 3), ArrivalProximity.unknown);
      expect(arrivalProximity(stopsRemaining: -1, etaMinutes: 3), ArrivalProximity.unknown);
    });
  });

  group('real fixtures — no live row ever lies with "here"', () {
    for (final stop in ['arrivals_zeleni_venac', 'arrivals_zvezdara_r5']) {
      test('$stop: every "here" is a genuinely near arrival', () {
        final board = _load(stop);
        for (final a in board.arrivals) {
          if (a.scheduled) continue;
          final p = arrivalProximity(
            stopsRemaining: a.stopsRemaining,
            etaMinutes: a.etaMinutes,
          );
          if (p == ArrivalProximity.here) {
            expect(a.etaMinutes, lessThanOrEqualTo(kHereEtaMinutes),
                reason: '${a.line}/${a.garageNo} shown "here" with eta ${a.etaMinutes}');
          }
          // A far-ETA row never gets a stops line claiming "here".
          if (a.etaMinutes > kHereEtaMinutes) {
            expect(p, isNot(ArrivalProximity.here));
          }
        }
      });
    }

    test('every Zeleni venac row is classified — none is a blank/void status', () {
      final board = _load('arrivals_zeleni_venac');
      expect(board.arrivals, isNotEmpty);
      var sawExpected = false;
      for (final a in board.arrivals) {
        final status = arrivalRowStatus(a);
        // The classifier is total: every row gets live | expected | scheduled,
        // so no row can render blank the way placeholder rows used to.
        expect(ArrivalRowStatus.values, contains(status));
        // Clickability == live, everywhere.
        expect(status == ArrivalRowStatus.live, arrivalHasLivePosition(a),
            reason: '${a.line}/${a.garageNo}');
        // The placeholder class (valid ETA, no live position) is "expected", not
        // blank and not a live lie.
        if (!a.scheduled && !arrivalHasLivePosition(a)) {
          expect(status, ArrivalRowStatus.expected);
          sawExpected = true;
        }
      }
      expect(sawExpected, isTrue,
          reason: 'Zeleni venac carries the placeholder (expected) class');
    });

    test('Zeleni venac: the junk 0-stops rows are the placeholder class (P1/P2), '
        'no longer "here", and correctly non-clickable', () {
      final board = _load('arrivals_zeleni_venac');
      final junk = board.arrivals.where((a) =>
          !a.scheduled && a.stopsRemaining == 0 && a.etaMinutes > kHereEtaMinutes);
      expect(junk, isNotEmpty, reason: 'fixture should contain the junk rows');
      final placeholders =
          junk.where((a) => isPlaceholderGarage(a.garageNo)).toList();
      expect(placeholders, isNotEmpty, reason: 'placeholder P1/P2 present');
      for (final a in junk) {
        // Not "here".
        expect(
          arrivalProximity(stopsRemaining: a.stopsRemaining, etaMinutes: a.etaMinutes),
          ArrivalProximity.unknown,
        );
      }
      for (final a in placeholders) {
        // Same class → correctly not a followable/map vehicle.
        expect(arrivalHasLivePosition(a), isFalse);
      }
    });
  });
}
