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

  group('stopMarkerType (type priority — tram dominates)', () {
    test('tram + night bus reads as tram, not mixed', () {
      // Real case: "Batutova" on Bul. kralja Aleksandra — trams 5/6/7L/14 plus
      // night buses 302N/307N. It must stay a tram stop.
      expect(stopMarkerType(_stop(['5', '6', '7L', '14', '302N', '307N'])), VehicleType.tram);
    });

    test('tram + trolley + bus still reads as tram', () {
      expect(stopMarkerType(_stop(['3', '29', '79'])), VehicleType.tram);
    });

    test('pure bus stop is a bus stop', () {
      expect(stopMarkerType(_stop(['79', '304N'])), VehicleType.bus);
    });

    test('pure tram stop is a tram stop', () {
      expect(stopMarkerType(_stop(['5', '6', '14'])), VehicleType.tram);
    });

    test('bus + trolley (no tram) is still the unified mixed marker', () {
      expect(stopMarkerType(_stop(['79', '29'])), isNull);
    });
  });

  group('stopImageFor', () {
    test('tram + night bus uses the tram image, not the mixed image', () {
      expect(stopImageFor(_stop(['5', '302N'])), MapImages.tram);
    });

    test('bus + trolley uses the mixed image', () {
      expect(stopImageFor(_stop(['79', '29'])), MapImages.mixedStop);
    });

    test('pure bus uses the bus image', () {
      expect(stopImageFor(_stop(['79'])), MapImages.bus);
    });
  });
}
