import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/search.dart';
import 'package:stize/domain/models/line_info.dart';
import 'package:stize/domain/models/nearby_arrival.dart';
import 'package:stize/domain/models/stop.dart';
import 'package:stize/domain/models/vehicle_type.dart';

NearbyGroup _group({
  required String line,
  String? destination,
  String stopId = 's',
  String stopName = 'Stop',
}) =>
    NearbyGroup(
      line: line,
      vehicleType: VehicleType.tram,
      destination: destination,
      routeId: 'r-$line',
      stopId: stopId,
      stopName: stopName,
      distanceMeters: 100,
      arrivals: const [],
    );

Stop _stop(String id, String name) =>
    Stop(stopId: id, name: name, lat: 0, lon: 0, lines: const []);

LineInfo _line(String line) => LineInfo(
      line: line,
      vehicleType: VehicleType.tram,
      routeId: 'route-$line',
      origin: 'A',
      destination: 'B',
    );

void main() {
  group('filterNearbyGroups', () {
    final groups = [
      _group(line: '12', destination: 'Banovo brdo', stopName: 'Batutova'),
      _group(line: '7', destination: 'Ustanička', stopName: 'Vukov spomenik'),
      _group(line: '79', destination: 'Zeleni venac', stopName: 'Batutova'),
    ];

    test('empty query returns the list unchanged', () {
      expect(filterNearbyGroups(groups, '   '), groups);
    });

    test('matches on line, destination, or stop name, case-insensitively', () {
      expect(filterNearbyGroups(groups, '79').map((g) => g.line), ['79']);
      expect(filterNearbyGroups(groups, 'banovo').map((g) => g.line), ['12']);
      // "Batutova" is the stop name of both 12 and 79.
      expect(filterNearbyGroups(groups, 'batutova').map((g) => g.line),
          ['12', '79']);
    });
  });

  group('mergeNearbyThenGlobal', () {
    test('nearby matches rank above every global result for the same query', () {
      final rows = mergeNearbyThenGlobal(
        nearby: [_group(line: '79', stopId: 'near-1')],
        stops: [_stop('g-1', 'Global Stop'), _stop('g-2', 'Another Stop')],
        lines: [_line('83')],
      );

      // Every nearby row precedes every stop/line row.
      final firstGlobal = rows.indexWhere((r) => r is! NearbySearchRow);
      expect(rows.first, isA<NearbySearchRow>());
      expect(firstGlobal, 1); // exactly one nearby row, then global begins
      expect(rows.sublist(firstGlobal).any((r) => r is NearbySearchRow), isFalse);

      // Order within global: stops before lines.
      expect(rows[1], isA<StopSearchRow>());
      expect(rows[2], isA<StopSearchRow>());
      expect(rows[3], isA<LineSearchRow>());
    });

    test('a global stop already surfaced as a nearby match is not repeated', () {
      final rows = mergeNearbyThenGlobal(
        nearby: [_group(line: '12', stopId: 'shared')],
        stops: [_stop('shared', 'Dup'), _stop('fresh', 'Fresh')],
        lines: [_line('12'), _line('44')], // line 12 dup'd by the nearby group
      );
      final stopIds = rows.whereType<StopSearchRow>().map((r) => r.stop.stopId);
      expect(stopIds, ['fresh']); // 'shared' de-duped
      final lineNums = rows.whereType<LineSearchRow>().map((r) => r.line.line);
      expect(lineNums, ['44']); // '12' de-duped
    });

    test('no nearby matches → only global rows, no leading section', () {
      final rows = mergeNearbyThenGlobal(
        nearby: const [],
        stops: [_stop('g', 'G')],
        lines: const [],
      );
      expect(rows.every((r) => r is! NearbySearchRow), isTrue);
      expect(rows.length, 1);
    });
  });
}
