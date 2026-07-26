import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/map_support.dart';
import 'package:stize/domain/models/line_info.dart';
import 'package:stize/domain/models/stop.dart';
import 'package:stize/domain/models/vehicle_type.dart';

// A stop carrying explicit authoritative types (as the GTFS build now emits).
Stop _typed(List<VehicleType> types) =>
    Stop(stopId: '1', name: 'X', lat: 44.8, lon: 20.4, lines: const [], types: types);

// A stop with only line numbers and no `types` (a bundle predating the field /
// the offline cache) — classification must fall back to the line→type index.
Stop _lines(List<String> lines) =>
    Stop(stopId: '1', name: 'X', lat: 44.8, lon: 20.4, lines: lines);

LineInfo _line(String line, VehicleType type) => LineInfo(
  line: line,
  vehicleType: type,
  routeId: line,
  origin: 'A',
  destination: 'B',
);

// The authoritative index as built from /api/v1/lines/all (feed route_type).
// The collision cases are the whole point: the letter/night-suffixed bus lines
// must resolve to bus, never to the tram/trolley their bare number would imply.
final _index = LineTypeIndex.fromLines([
  _line('2', VehicleType.tram),
  _line('7L', VehicleType.tram),
  _line('11', VehicleType.tram),
  _line('13', VehicleType.tram),
  _line('40', VehicleType.trolleybus),
  _line('2A', VehicleType.bus),
  _line('3A', VehicleType.bus),
  _line('9A', VehicleType.bus),
  _line('21A', VehicleType.bus),
  _line('29N', VehicleType.bus),
  _line('79', VehicleType.bus),
  _line('302N', VehicleType.bus),
]);

void main() {
  setUp(() => setLineTypeIndex(_index));
  tearDown(() => setLineTypeIndex(LineTypeIndex.empty));

  group('LineTypeIndex — type by feed, not by number', () {
    test('suffixed bus lines that collide with tram numbers stay bus', () {
      // The reported defect: "3A"/"2A"/"9A" are buses (route_type 3), not the
      // trams "3"/"2"/"9" their numeric prefix would suggest.
      expect(_index.typeOf('3A'), VehicleType.bus);
      expect(_index.typeOf('2A'), VehicleType.bus);
      expect(_index.typeOf('9A'), VehicleType.bus);
    });

    test('lines that collide with trolley numbers stay bus', () {
      // "21A" is a bus variant of trolley 21; "29N" is the night bus on the 29
      // corridor. Both are route_type 3 in the feed.
      expect(_index.typeOf('21A'), VehicleType.bus);
      expect(_index.typeOf('29N'), VehicleType.bus);
    });

    test('real trams and trolleys keep their feed type', () {
      expect(_index.typeOf('11'), VehicleType.tram);
      expect(_index.typeOf('7L'), VehicleType.tram);
      expect(_index.typeOf('40'), VehicleType.trolleybus);
    });

    test('an unknown line falls back to bus (never invents a tram)', () {
      expect(_index.typeOf('ADA 3'), VehicleType.bus);
    });

    test('tramLineNumbers lists only feed-typed trams (no absent 3/7/9)', () {
      final trams = tramLineNumbers.toSet();
      expect(trams, containsAll(<String>['2', '7L', '11', '13']));
      expect(trams.contains('3'), isFalse); // absent from the feed entirely
      expect(trams.contains('3A'), isFalse); // a bus
    });
  });

  group('stopMarkerType — tram dominance preserved, fed authoritative types', () {
    test('tram + night bus reads as tram, not mixed (from per-stop types)', () {
      // Real case: "Batutova" — trams plus night buses. Stays a tram stop.
      expect(stopMarkerType(_typed([VehicleType.tram, VehicleType.bus])), VehicleType.tram);
    });

    test('tram + trolley + bus still reads as tram', () {
      expect(
        stopMarkerType(_typed([VehicleType.tram, VehicleType.trolleybus, VehicleType.bus])),
        VehicleType.tram,
      );
    });

    test('pure bus stop is a bus stop', () {
      expect(stopMarkerType(_typed([VehicleType.bus])), VehicleType.bus);
    });

    test('bus + trolley (no tram) is the unified mixed marker', () {
      expect(stopMarkerType(_typed([VehicleType.bus, VehicleType.trolleybus])), isNull);
    });

    test('a 3A/49/94 stop (all buses) is a BUS stop — the Topčiderski park bug', () {
      // Before the fix this rendered as a tram because "3A" → "3" → tram.
      expect(stopMarkerType(_lines(['3A', '49', '94'])), VehicleType.bus);
    });
  });

  group('stopImageFor', () {
    test('tram + night bus uses the tram image', () {
      expect(stopImageFor(_typed([VehicleType.tram, VehicleType.bus])), MapImages.tram);
    });

    test('bus + trolley uses the mixed image', () {
      expect(stopImageFor(_typed([VehicleType.bus, VehicleType.trolleybus])), MapImages.mixedStop);
    });

    test('pure bus uses the bus image', () {
      expect(stopImageFor(_typed([VehicleType.bus])), MapImages.bus);
    });
  });

  group('fallback: no per-stop types → resolve line numbers via the index', () {
    test('a real tram line + a night bus reads as tram', () {
      expect(stopMarkerType(_lines(['11', '302N'])), VehicleType.tram);
    });

    test('a colliding bus line does NOT read as tram', () {
      expect(stopMarkerType(_lines(['3A', '79'])), VehicleType.bus);
    });
  });
}
