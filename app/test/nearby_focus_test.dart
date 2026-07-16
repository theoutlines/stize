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

  group('visibleNearbyEtas — same live/scheduled dedup as the arrivals list', () {
    test('scheduled earlier than a live departure is dropped', () {
      final group = _group(arrivals: [
        _eta(scheduled: true, eta: 6), // ≤ live 9 → same vehicle, hidden
        _eta(scheduled: false, garageNo: 'P70260', eta: 9),
      ]);
      final visible = visibleNearbyEtas(group);
      expect(visible.map((e) => e.etaMinutes), [9]);
    });

    test('scheduled later than the live horizon is kept (and still flagged)', () {
      final group = _group(arrivals: [
        _eta(scheduled: false, garageNo: 'P70260', eta: 9),
        _eta(scheduled: true, eta: 24), // > 9 → a real later plan, kept
      ]);
      final visible = visibleNearbyEtas(group);
      expect(visible.map((e) => e.etaMinutes), [9, 24]);
      expect(visible.map((e) => nearbyEtaIsLive(e)), [true, false]);
    });

    test('a placeholder departure at/under the live horizon is dropped too', () {
      final group = _group(arrivals: [
        _eta(scheduled: false, garageNo: 'P2', eta: 4), // placeholder ≤ 9 → hidden
        _eta(scheduled: false, garageNo: 'P70260', eta: 9),
      ]);
      expect(visibleNearbyEtas(group).map((e) => e.etaMinutes), [9]);
    });

    test('a schedule-only group is returned unchanged (never emptied)', () {
      final group = _group(arrivals: [
        _eta(scheduled: true, eta: 6),
        _eta(scheduled: true, eta: 24),
      ]);
      expect(visibleNearbyEtas(group).map((e) => e.etaMinutes), [6, 24]);
    });
  });
}
