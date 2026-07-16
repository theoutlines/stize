import 'package:flutter_test/flutter_test.dart';
import 'package:stigla/core/nearby_focus.dart';
import 'package:stigla/domain/models/arrival.dart';
import 'package:stigla/domain/models/nearby_arrival.dart';
import 'package:stigla/domain/models/vehicle_type.dart';

NearbyGroup _group({
  required List<NearbyEta> arrivals,
  String line = '79',
  String routeId = '00079-1',
}) =>
    NearbyGroup(
      line: line,
      vehicleType: VehicleType.bus,
      destination: 'Dorćol',
      routeId: routeId,
      stopId: '20091',
      stopName: 'Batutova',
      distanceMeters: 60,
      arrivals: arrivals,
    );

NearbyEta _eta({required bool scheduled, String? garageNo, int eta = 3}) => NearbyEta(
      etaMinutes: eta,
      garageNo: garageNo,
      stopsRemaining: 2,
      isScheduled: scheduled,
    );

Arrival _arr({
  required String garageNo,
  required bool scheduled,
  String line = '79',
  String dir = '00079-1',
  int eta = 3,
  LatLon? gps = const LatLon(44.8, 20.47),
}) =>
    Arrival(
      line: line,
      vehicleType: VehicleType.bus,
      etaMinutes: eta,
      stopsRemaining: 2,
      routeId: '00079',
      directionRouteId: dir,
      gps: scheduled ? null : gps,
      garageNo: scheduled ? null : garageNo,
      scheduled: scheduled,
    );

void main() {
  group('nearbyFollowTarget — schedule-only rows open the stop, never a phantom', () {
    test('a schedule-only group returns null (→ open the stop)', () {
      final group = _group(arrivals: [_eta(scheduled: true)]);
      final board = [_arr(garageNo: 'P70260', scheduled: false)]; // even if a live sibling exists
      expect(nearbyFollowTarget(group, board), isNull);
    });

    test('a live group follows the matching live vehicle by garage no', () {
      final group = _group(arrivals: [_eta(scheduled: false, garageNo: 'P70260')]);
      final board = [
        _arr(garageNo: 'P99999', scheduled: false, eta: 1), // sooner, but not the row's vehicle
        _arr(garageNo: 'P70260', scheduled: false, eta: 5),
      ];
      final target = nearbyFollowTarget(group, board);
      expect(target?.garageNo, 'P70260');
    });

    test('a live group with no garage id follows the soonest live of the line×dir', () {
      // Real garage ids (P≥1000); P1/P2 would be junk placeholders and get filtered.
      final group = _group(arrivals: [_eta(scheduled: false, garageNo: null)]);
      final board = [
        _arr(garageNo: 'P70002', scheduled: false, eta: 8),
        _arr(garageNo: 'P70001', scheduled: false, eta: 2),
      ];
      expect(nearbyFollowTarget(group, board)?.garageNo, 'P70001');
    });

    test('a live-looking group whose board has no live match returns null (drifted status)', () {
      final group = _group(arrivals: [_eta(scheduled: false, garageNo: 'P70260')]);
      final board = [_arr(garageNo: 'x', scheduled: true)]; // board says scheduled now
      expect(nearbyFollowTarget(group, board), isNull);
    });

    test('never returns a scheduled arrival even if line×dir matches', () {
      final group = _group(arrivals: [_eta(scheduled: false, garageNo: 'P70260')]);
      final board = [_arr(garageNo: 'P70260', scheduled: true)];
      expect(nearbyFollowTarget(group, board), isNull);
    });
  });
}
