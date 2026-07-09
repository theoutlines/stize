import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:stigla/core/route_path.dart';
import 'package:stigla/core/vehicle_track_animator.dart';
import 'package:stigla/domain/models/arrival.dart';
import 'package:stigla/domain/models/vehicle_type.dart';

Arrival _arrival({required String garageNo, required double lat, required double lon}) {
  return Arrival(
    line: '79',
    vehicleType: VehicleType.bus,
    etaMinutes: 5,
    stopsRemaining: 3,
    routeId: '00079',
    gps: LatLon(lat, lon),
    garageNo: garageNo,
  );
}

void main() {
  test('a brand-new vehicle snaps directly to its first known position', () {
    final animator = VehicleTrackAnimator();
    animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 0);

    final pos = animator.positionOf('P1', 0);
    expect(pos.latitude, 44.80);
    expect(pos.longitude, 20.50);
  });

  test('never overshoots the latest known real position', () {
    final animator = VehicleTrackAnimator();
    animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 0);

    // A fresh fix arrives further along the route.
    animator.sync([_arrival(garageNo: 'P1', lat: 44.81, lon: 20.51)], 1.0);

    // At t=1 (animation fully played out) it must be exactly at the new fix,
    // never beyond it.
    final atEnd = animator.positionOf('P1', 1.0);
    expect(atEnd.latitude, 44.81);
    expect(atEnd.longitude, 20.51);

    // Halfway through, it must be strictly between the two real fixes.
    final atHalf = animator.positionOf('P1', 0.5);
    expect(atHalf.latitude, greaterThan(44.80));
    expect(atHalf.latitude, lessThan(44.81));
  });

  test('a resync mid-animation starts from the current interpolated spot, not from scratch', () {
    final animator = VehicleTrackAnimator();
    animator.sync([_arrival(garageNo: 'P1', lat: 0.0, lon: 0.0)], 0);
    animator.sync([_arrival(garageNo: 'P1', lat: 10.0, lon: 0.0)], 0); // first real move, starts at t=0

    // Halfway to the first target (t=0.5) the vehicle should be at lat 5.0.
    expect(animator.positionOf('P1', 0.5).latitude, 5.0);

    // A new fix lands right at that halfway point (t=0.5), continuing further on.
    animator.sync([_arrival(garageNo: 'P1', lat: 20.0, lon: 0.0)], 0.5);

    // The new leg must start from where it visually was (lat 5.0), not
    // jump back to the old target (10.0) or the old start (0.0).
    expect(animator.positionOf('P1', 0.0).latitude, 5.0);
    expect(animator.positionOf('P1', 1.0).latitude, 20.0);
  });

  test('holds a briefly-missing vehicle through a grace period, then drops it', () {
    final animator = VehicleTrackAnimator();
    animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 0);
    expect(animator.tracks.containsKey('P1'), isTrue);
    expect(animator.opacityFor('P1'), 1.0);

    // Missing from one update — held (faded), not dropped (X6 data blip).
    animator.sync([], 1.0);
    expect(animator.tracks.containsKey('P1'), isTrue);
    expect(animator.opacityFor('P1'), lessThan(1.0));

    // Still missing on the next — still within grace.
    animator.sync([], 1.0);
    expect(animator.tracks.containsKey('P1'), isTrue);

    // Missing beyond the grace period — now dropped.
    animator.sync([], 1.0);
    expect(animator.tracks.containsKey('P1'), isFalse);
  });

  test('clear() drops everything immediately (zoom-out reset)', () {
    final animator = VehicleTrackAnimator();
    animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 0);
    expect(animator.tracks, isNotEmpty);
    animator.clear();
    expect(animator.tracks, isEmpty);
  });

  test('with a route path, moves along the route, not diagonally (X5)', () {
    // L-shaped route A(east)->B(north)->C; vehicle jumps from A to C.
    final path = RoutePath.fromLatLon([
      [44.80, 20.50],
      [44.80, 20.52],
      [44.81, 20.52],
    ]);
    final animator = VehicleTrackAnimator();
    animator.syncSamples([
      VehicleSample(
        key: 'P1',
        position: const ll.LatLng(44.80, 20.50), // at A
        line: '2',
        type: VehicleType.tram,
        path: path,
      ),
    ], 0);
    animator.syncSamples([
      VehicleSample(
        key: 'P1',
        position: const ll.LatLng(44.81, 20.52), // at C
        line: '2',
        type: VehicleType.tram,
        path: path,
      ),
    ], 1.0);

    // Halfway through the animation, a straight line A->C would put the marker
    // at the diagonal midpoint (~44.805, 20.51). Following the route instead
    // keeps it near the eastward first leg (lon ~20.52), off that diagonal.
    final mid = animator.positionOf('P1', 0.5);
    expect(mid.longitude, closeTo(20.52, 3e-3));
    // Heading tracks the route direction (east on the first leg here).
    final h = animator.headingAt('P1', 0.5)!;
    expect(h, closeTo(90, 5));
  });

  test('flags a vehicle as stuck after repeated no-move updates', () {
    final animator = VehicleTrackAnimator();
    // First fix: brand new, moving by default.
    animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 0);
    expect(animator.isStuck('P1'), isFalse);

    // Same position again — one stale update, still normal dwell (below thr).
    animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 1.0);
    expect(animator.isStuck('P1'), isFalse);

    // Second consecutive no-move update — still within normal dwell.
    animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 1.0);
    expect(animator.isStuck('P1'), isFalse);

    // Third consecutive no-move update (~90s) — now it reads as stuck.
    animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 1.0);
    expect(animator.isStuck('P1'), isTrue);

    // It moves again → back to moving.
    animator.sync([_arrival(garageNo: 'P1', lat: 44.82, lon: 20.52)], 1.0);
    expect(animator.isStuck('P1'), isFalse);
  });

  test('carries the line and type onto the track', () {
    final animator = VehicleTrackAnimator();
    animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 0);
    final track = animator.trackFor('P1');
    expect(track?.line, '79');
    expect(track?.type, VehicleType.bus);
  });

  test('ignores arrivals with no GPS fix', () {
    final animator = VehicleTrackAnimator();
    final noGps = Arrival(
      line: '5',
      vehicleType: VehicleType.tram,
      etaMinutes: 2,
      stopsRemaining: null,
      routeId: '00005',
      gps: null,
      garageNo: 'T1',
    );
    animator.sync([noGps], 0);
    expect(animator.tracks, isEmpty);
  });
}
