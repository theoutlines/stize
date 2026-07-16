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

  group('visibleNearbyEtas — a live card never mixes in scheduled times', () {
    test('a live group shows ONLY live times; scheduled tail is dropped', () {
      // Owner: "7L → Ustanička · 2 min / 11 min (clock)" — the 11 must go.
      final group = _group(arrivals: [
        _eta(scheduled: false, garageNo: 'P70260', eta: 2),
        _eta(scheduled: true, eta: 11), // scheduled → not on a live card
      ]);
      final visible = visibleNearbyEtas(group);
      expect(visible.map((e) => e.etaMinutes), [2]);
      expect(visible.every(nearbyEtaIsLive), isTrue);
    });

    test('two live departures are both kept', () {
      final group = _group(arrivals: [
        _eta(scheduled: false, garageNo: 'P70260', eta: 2),
        _eta(scheduled: false, garageNo: 'P70261', eta: 9),
      ]);
      expect(visibleNearbyEtas(group).map((e) => e.etaMinutes), [2, 9]);
    });

    test('a placeholder time is not "live" and is dropped from a live card', () {
      final group = _group(arrivals: [
        _eta(scheduled: false, garageNo: 'P70260', eta: 2), // real live
        _eta(scheduled: false, garageNo: 'P2', eta: 9), // placeholder → dropped
      ]);
      expect(visibleNearbyEtas(group).map((e) => e.etaMinutes), [2]);
    });

    test('a schedule-only group is returned unchanged (never emptied)', () {
      final group = _group(arrivals: [
        _eta(scheduled: true, eta: 6),
        _eta(scheduled: true, eta: 24),
      ]);
      expect(visibleNearbyEtas(group).map((e) => e.etaMinutes), [6, 24]);
    });
  });

  group('orderNearbyGroups — live cards first, then schedule-only, each by ETA', () {
    NearbyGroup g(String line, {required bool live, required int eta}) => _group(
          line: line,
          routeId: '$line-0',
          arrivals: [
            _eta(scheduled: !live, garageNo: live ? 'P70260' : null, eta: eta),
          ],
        );

    test('a schedule-only card, however soon, sorts below every live card', () {
      final ordered = orderNearbyGroups([
        g('7L', live: false, eta: 1), // schedule-only, soonest overall
        g('79', live: true, eta: 9),
        g('5', live: true, eta: 4),
      ]);
      // Live section first (by ETA: 5@4, 79@9), then schedule-only 7L.
      expect(ordered.map((x) => x.line), ['5', '79', '7L']);
    });

    test('stable within a section for equal ETAs (keeps incoming order)', () {
      final ordered = orderNearbyGroups([
        g('A', live: true, eta: 5),
        g('B', live: true, eta: 5),
      ]);
      expect(ordered.map((x) => x.line), ['A', 'B']);
    });
  });
}
