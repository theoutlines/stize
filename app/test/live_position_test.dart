import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/live_position.dart';
import 'package:stize/domain/models/arrival.dart';
import 'package:stize/domain/models/area_vehicle.dart';
import 'package:stize/domain/models/vehicle_type.dart';

Arrival _arrival({String? garageNo, LatLon? gps, bool scheduled = false}) => Arrival(
      line: '71',
      vehicleType: VehicleType.bus,
      etaMinutes: 3,
      stopsRemaining: 2,
      routeId: '00071',
      gps: gps,
      garageNo: garageNo,
      scheduled: scheduled,
    );

AreaVehicle _area({String? garageNo}) => AreaVehicle(
      line: '71',
      vehicleType: VehicleType.bus,
      garageNo: garageNo,
      lat: 44.81,
      lon: 20.45,
      heading: 90,
    );

void main() {
  group('isPlaceholderGarage', () {
    test('P1..P999 are placeholders', () {
      for (final g in ['P1', 'P2', 'P6', 'P999', 'p42']) {
        expect(isPlaceholderGarage(g), isTrue, reason: g);
      }
    });

    test('real garage ids (>= P1000) are not placeholders', () {
      for (final g in ['P1000', 'P70260', 'P58406', 'P28201']) {
        expect(isPlaceholderGarage(g), isFalse, reason: g);
      }
    });

    test('null / blank / non-P ids are not placeholders (missing id, not junk)', () {
      expect(isPlaceholderGarage(null), isFalse);
      expect(isPlaceholderGarage(''), isFalse);
      expect(isPlaceholderGarage('   '), isFalse);
      expect(isPlaceholderGarage('12345'), isFalse); // no leading P
      expect(isPlaceholderGarage('BG123'), isFalse);
    });
  });

  group('arrivalHasLivePosition', () {
    test('real vehicle with a GPS fix is live', () {
      expect(
        arrivalHasLivePosition(_arrival(garageNo: 'P70260', gps: const LatLon(44.82, 20.44))),
        isTrue,
      );
    });

    test('placeholder row (junk garage, GPS on stop) is not live', () {
      expect(
        arrivalHasLivePosition(_arrival(garageNo: 'P1', gps: const LatLon(44.814, 20.4556))),
        isFalse,
      );
    });

    test('no GPS is never live, whatever the garage', () {
      expect(arrivalHasLivePosition(_arrival(garageNo: 'P70260', gps: null)), isFalse);
      expect(arrivalHasLivePosition(_arrival(garageNo: null, gps: null)), isFalse);
    });

    test('real GPS but missing garage id is still trusted as live', () {
      expect(
        arrivalHasLivePosition(_arrival(garageNo: null, gps: const LatLon(44.82, 20.44))),
        isTrue,
      );
    });

    test('a scheduled arrival is NEVER live, even with a GPS + real garage', () {
      // The map is live-only: a schedule-predicted departure must not become a
      // marker (or be followable), whatever fields it carries.
      expect(
        arrivalHasLivePosition(_arrival(
          garageNo: 'P70260',
          gps: const LatLon(44.82, 20.44),
          scheduled: true,
        )),
        isFalse,
      );
    });
  });

  group('areaVehicleHasLivePosition', () {
    test('real garage is live, junk garage is not', () {
      expect(areaVehicleHasLivePosition(_area(garageNo: 'P70260')), isTrue);
      expect(areaVehicleHasLivePosition(_area(garageNo: 'P1')), isFalse);
      expect(areaVehicleHasLivePosition(_area(garageNo: null)), isTrue);
    });
  });
}
