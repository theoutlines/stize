import 'package:flutter_test/flutter_test.dart';
import 'package:stigla/core/eta_delta.dart';
import 'package:stigla/domain/models/arrival.dart';
import 'package:stigla/domain/models/vehicle_type.dart';

/// A genuinely live vehicle: real GPS, real garage.
Arrival _live(String line, int eta, {String garage = '101'}) => Arrival(
      line: line,
      vehicleType: VehicleType.bus,
      etaMinutes: eta,
      stopsRemaining: null,
      routeId: 'r1',
      directionRouteId: 'r1',
      gps: const LatLon(44.8, 20.4),
      garageNo: garage,
    );

/// A placeholder ("expected") row: valid ETA, no live position (garage P#).
Arrival _expected(String line, int eta) => Arrival(
      line: line,
      vehicleType: VehicleType.bus,
      etaMinutes: eta,
      stopsRemaining: 0,
      routeId: 'r1',
      directionRouteId: 'r1',
      gps: const LatLon(44.8, 20.4),
      garageNo: 'P1',
    );

/// A timetable-fallback row (`source: scheduled`).
Arrival _scheduled(String line, int eta) => Arrival(
      line: line,
      vehicleType: VehicleType.bus,
      etaMinutes: eta,
      stopsRemaining: null,
      routeId: 'r1',
      directionRouteId: 'r1',
      gps: null,
      garageNo: null,
      scheduled: true,
    );

ArrivalsBoard _board(DateTime updatedAt, List<Arrival> arrivals) => ArrivalsBoard(
      stopId: 's1',
      stopName: 'Stop',
      updatedAt: updatedAt,
      arrivals: arrivals,
      serviceStatus: ServiceStatus.ok,
    );

void main() {
  final t0 = DateTime.utc(2026, 7, 17, 15, 24, 0);

  group('diffEtaDeltas', () {
    test('the clock merely ticking produces no badge (the main case)', () {
      // Poll 1: as-of 15:24:00, ETA 18 → arriving 15:42:00.
      final first = diffEtaDeltas(const {}, _board(t0, [_live('26', 18)]));
      // Poll 2, 50s later: the same prediction now reads one minute lower (17)
      // purely because the clock advanced — arriving 15:41:50, a 10s wobble.
      final second = diffEtaDeltas(
        first.arrivalTimes,
        _board(t0.add(const Duration(seconds: 50)), [_live('26', 17)]),
      );
      expect(second.deltas, isEmpty);
    });

    test('no badge on the very first sighting (no baseline)', () {
      final r = diffEtaDeltas(const {}, _board(t0, [_live('26', 18)]));
      expect(r.deltas, isEmpty);
      expect(r.arrivalTimes['101'], t0.add(const Duration(minutes: 18)));
    });

    test('a real forward slip flags a "later" (↑, positive) badge', () {
      final first = diffEtaDeltas(const {}, _board(t0, [_live('26', 18)]));
      // Next poll, same instant, but ETA jumped to 21 → arriving 3 min later.
      final second = diffEtaDeltas(
        first.arrivalTimes,
        _board(t0, [_live('26', 21)]),
      );
      expect(second.deltas['101'], 3);
    });

    test('a real earlier reforecast flags a "sooner" (↓, negative) badge', () {
      final first = diffEtaDeltas(const {}, _board(t0, [_live('26', 18)]));
      final second = diffEtaDeltas(
        first.arrivalTimes,
        _board(t0, [_live('26', 16)]),
      );
      expect(second.deltas['101'], -2);
    });

    test('a sub-threshold arrival shift (< 45s) is noise, no badge', () {
      // Same ETA minute, board 40s later → arrival instant moved only 40s.
      final first = diffEtaDeltas(const {}, _board(t0, [_live('26', 10)]));
      final second = diffEtaDeltas(
        first.arrivalTimes,
        _board(t0.add(const Duration(seconds: 40)), [_live('26', 10)]),
      );
      expect(second.deltas, isEmpty);
    });

    test('a change just past the threshold shows at least 1 min, never 0', () {
      // Board 50s later AND ETA held at 10 → arrival instant slipped 50s later:
      // past the 45s threshold, rounds to 1 min, must not vanish as 0.
      final first = diffEtaDeltas(const {}, _board(t0, [_live('26', 10)]));
      final second = diffEtaDeltas(
        first.arrivalTimes,
        _board(t0.add(const Duration(seconds: 50)), [_live('26', 10)]),
      );
      expect(second.deltas['101'], 1);
    });

    test('a changed vehicle in the row (different garage) gets no delta', () {
      final first = diffEtaDeltas(const {}, _board(t0, [_live('26', 18, garage: '101')]));
      // Same line/position next poll but a different bus — nothing to diff.
      final second = diffEtaDeltas(
        first.arrivalTimes,
        _board(t0, [_live('26', 10, garage: '202')]),
      );
      expect(second.deltas, isEmpty);
      expect(second.arrivalTimes.containsKey('202'), isTrue);
    });

    test('expected and scheduled rows never earn a badge', () {
      final first = diffEtaDeltas(
        const {},
        _board(t0, [_expected('26', 18), _scheduled('83', 12)]),
      );
      // Even with a big ETA move, non-live rows are ignored entirely.
      final second = diffEtaDeltas(
        first.arrivalTimes,
        _board(t0, [_expected('26', 30), _scheduled('83', 40)]),
      );
      expect(first.arrivalTimes, isEmpty);
      expect(second.deltas, isEmpty);
    });

    test('a whole board of clock-ticks stays silent — no synchronised flash', () {
      final buses = [
        for (var i = 0; i < 6; i++) _live('$i', 10 + i, garage: 'g$i'),
      ];
      final first = diffEtaDeltas(const {}, _board(t0, buses));
      // 50s later every count-down has ticked down one minute together.
      final ticked = [
        for (var i = 0; i < 6; i++) _live('$i', 9 + i, garage: 'g$i'),
      ];
      final second = diffEtaDeltas(
        first.arrivalTimes,
        _board(t0.add(const Duration(seconds: 50)), ticked),
      );
      expect(second.deltas, isEmpty);
    });
  });
}
