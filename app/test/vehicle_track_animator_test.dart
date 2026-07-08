import 'package:flutter_test/flutter_test.dart';

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

  test('drops a vehicle once it no longer appears in the arrivals list', () {
    final animator = VehicleTrackAnimator();
    animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 0);
    expect(animator.tracks.containsKey('P1'), isTrue);

    animator.sync([], 1.0);
    expect(animator.tracks.containsKey('P1'), isFalse);
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
