import 'package:flutter_test/flutter_test.dart';
import 'package:stigla/core/arrival_grouping.dart';
import 'package:stigla/domain/models/arrival.dart';
import 'package:stigla/domain/models/vehicle_type.dart';

/// A genuinely live vehicle: real GPS, real garage.
Arrival _live(String line, int eta, {String route = 'r1', String garage = '101'}) =>
    Arrival(
      line: line,
      vehicleType: VehicleType.bus,
      etaMinutes: eta,
      stopsRemaining: null,
      routeId: route,
      directionRouteId: route,
      gps: const LatLon(44.8, 20.4),
      garageNo: garage,
    );

/// A placeholder ("expected") row: valid ETA, no live position (garage P#, GPS
/// pinned to the stop) — classified [ArrivalRowStatus.expected].
Arrival _expected(String line, int eta, {String route = 'r1'}) => Arrival(
      line: line,
      vehicleType: VehicleType.bus,
      etaMinutes: eta,
      stopsRemaining: 0,
      routeId: route,
      directionRouteId: route,
      gps: const LatLon(44.8, 20.4),
      garageNo: 'P1',
    );

/// A timetable-fallback row (`source: scheduled`).
Arrival _scheduled(String line, int eta, {String route = 'r1'}) => Arrival(
      line: line,
      vehicleType: VehicleType.bus,
      etaMinutes: eta,
      stopsRemaining: null,
      routeId: route,
      directionRouteId: route,
      gps: null,
      garageNo: null,
      scheduled: true,
    );

List<ArrivalRow> _rows(List<ArrivalListEntry> e) => e.whereType<ArrivalRow>().toList();
List<ScheduledGroupCell> _cells(List<ArrivalListEntry> e) =>
    e.whereType<ScheduledGroupCell>().toList();

void main() {
  group('groupArrivals — live/scheduled dedup + scheduled collapse', () {
    test('Batutova case: live [2,14] suppresses scheduled 6, cell keeps 18/26/30', () {
      final entries = groupArrivals([
        _live('79', 2),
        _live('79', 14),
        _scheduled('79', 6),
        _scheduled('79', 18),
        _scheduled('79', 26),
        _scheduled('79', 30),
      ]);

      final rows = _rows(entries);
      expect(rows.map((r) => r.arrival.etaMinutes), [2, 14],
          reason: 'both live rows kept, sorted by ETA');

      final cells = _cells(entries);
      expect(cells, hasLength(1));
      expect(cells.single.line, '79');
      expect(cells.single.etaMinutes, [18, 26, 30],
          reason: 'scheduled 6 (≤ horizon 14) suppressed; next three collapse');
    });

    test('only scheduled: no suppression, collapses to nearest + two (max three)', () {
      final entries = groupArrivals([
        _scheduled('83', 5),
        _scheduled('83', 15),
        _scheduled('83', 25),
        _scheduled('83', 35),
      ]);
      expect(_rows(entries), isEmpty);
      final cell = _cells(entries).single;
      expect(cell.etaMinutes, [5, 15, 25], reason: 'never more than three times');
    });

    test('only live: every vehicle keeps its own row, no cell', () {
      final entries = groupArrivals([_live('26', 9), _live('26', 3)]);
      expect(_cells(entries), isEmpty);
      expect(_rows(entries).map((r) => r.arrival.etaMinutes), [3, 9]);
    });

    test('scheduled strictly beyond horizon survives; at/before is suppressed', () {
      final entries = groupArrivals([
        _live('7', 10),
        _scheduled('7', 4), // before horizon → hidden
        _scheduled('7', 12), // beyond → survives
      ]);
      expect(_cells(entries).single.etaMinutes, [12]);
    });

    test('exactly on the horizon is suppressed (not "strictly beyond")', () {
      final entries = groupArrivals([
        _live('7', 10),
        _scheduled('7', 10), // == horizon → hidden
        _scheduled('7', 11), // > horizon → survives
      ]);
      expect(_cells(entries).single.etaMinutes, [11]);
    });

    test('whole scheduled group suppressed → no cell at all', () {
      final entries = groupArrivals([
        _live('7', 20),
        _scheduled('7', 5),
        _scheduled('7', 15),
      ]);
      expect(_cells(entries), isEmpty);
      expect(_rows(entries).map((r) => r.arrival.etaMinutes), [20]);
    });

    test('two lines at a stop form two groups, ordered by nearest event', () {
      final entries = groupArrivals([
        _scheduled('83', 12),
        _live('79', 3),
      ]);
      // 79 (live, 3 min) is nearer than 83 (scheduled, 12 min).
      expect(entries.first, isA<ArrivalRow>());
      expect((entries.first as ArrivalRow).arrival.line, '79');
      final cell = _cells(entries).single;
      expect(cell.line, '83');
    });

    test('one line, two directions → two independent groups', () {
      final entries = groupArrivals([
        _live('3', 5, route: 'dirA'),
        _scheduled('3', 5, route: 'dirA'), // == horizon in dir A → suppressed
        _scheduled('3', 8, route: 'dirB'), // dir B has no live → survives
      ]);
      final cells = _cells(entries);
      expect(cells, hasLength(1), reason: 'only dir B keeps a scheduled cell');
      expect(cells.single.etaMinutes, [8]);
      expect(_rows(entries).map((r) => r.arrival.etaMinutes), [5]);
    });

    test('Expected is NOT collapsed and NOT hidden when beyond horizon', () {
      final entries = groupArrivals([
        _live('12', 4),
        _expected('12', 9), // beyond horizon 4 → own row, not a cell
        _scheduled('12', 20),
      ]);
      final rows = _rows(entries);
      // Order within group: live first, then expected, then the scheduled cell.
      expect(rows.map((r) => r.arrival.etaMinutes), [4, 9]);
      expect(entries.last, isA<ScheduledGroupCell>());
      expect((entries.last as ScheduledGroupCell).etaMinutes, [20]);
    });

    test('Expected at/before horizon is suppressed like Scheduled', () {
      final entries = groupArrivals([
        _live('12', 10),
        _expected('12', 6), // ≤ horizon → hidden (same physical vehicle)
      ]);
      expect(_rows(entries).map((r) => r.arrival.etaMinutes), [10]);
    });

    test('no live in group: expected keeps its row, scheduled still collapses', () {
      final entries = groupArrivals([
        _expected('5', 7),
        _scheduled('5', 11),
        _scheduled('5', 19),
      ]);
      expect(_rows(entries).map((r) => r.arrival.etaMinutes), [7]);
      expect(_cells(entries).single.etaMinutes, [11, 19]);
    });

    test('empty board → empty list', () {
      expect(groupArrivals(const []), isEmpty);
    });
  });
}
