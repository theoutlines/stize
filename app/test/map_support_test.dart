import 'package:flutter_test/flutter_test.dart';
import 'package:stigla/core/map_support.dart';
import 'package:stigla/domain/models/stop.dart';
import 'package:stigla/domain/models/vehicle_type.dart';

Stop _stop(List<String> lines) => Stop(stopId: '1', name: 'X', lat: 44.8, lon: 20.4, lines: lines);

void main() {
  group('classifyLine', () {
    test('tram numbers classify as tram', () {
      for (final l in ['2', '3', '5', '6', '7', '9', '10', '11', '12', '13', '14']) {
        expect(classifyLine(l), VehicleType.tram, reason: 'line $l');
      }
    });

    test('trolleybus numbers classify as trolleybus', () {
      for (final l in ['19', '21', '22', '28', '29', '40', '41']) {
        expect(classifyLine(l), VehicleType.trolleybus, reason: 'line $l');
      }
    });

    test('other numbers (and letter-suffixed variants) fall back to bus', () {
      expect(classifyLine('79'), VehicleType.bus);
      expect(classifyLine('304N'), VehicleType.bus);
      expect(classifyLine('E9'), VehicleType.bus);
    });

    test('numeric prefix is what matters, not a letter suffix', () {
      // "7L" shares the tram "7" numeric prefix.
      expect(classifyLine('7L'), VehicleType.tram);
    });
  });

  group('stopPrimaryType', () {
    test('a stop served by any tram line reads as a tram stop', () {
      expect(stopPrimaryType(_stop(['79', '3', '26'])), VehicleType.tram);
    });

    test('trolleybus wins over bus when no tram present', () {
      expect(stopPrimaryType(_stop(['79', '29'])), VehicleType.trolleybus);
    });

    test('bus-only stop is a bus stop', () {
      expect(stopPrimaryType(_stop(['79', '304', '26'])), VehicleType.bus);
    });
  });
}
