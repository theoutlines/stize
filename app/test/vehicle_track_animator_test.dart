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

    // Held (and fading further) across the whole grace window.
    for (var i = 0; i < 3; i++) {
      animator.sync([], 1.0);
      expect(animator.tracks.containsKey('P1'), isTrue);
    }

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

  test('stays on the correct leg of a fold-back route instead of snapping to the parallel one (F1)', () {
    // Out-and-back: east along lat 44.8000, then back west along lat 44.8003
    // (~33 m north). The legs run parallel and close, so a fix on the return
    // leg is geometrically near the outbound leg too.
    final path = RoutePath.fromLatLon([
      [44.8000, 20.5000],
      [44.8000, 20.5200],
      [44.8003, 20.5200],
      [44.8003, 20.5000],
    ]);
    final animator = VehicleTrackAnimator();
    // Vehicle starts on the outbound leg, mid-way.
    animator.syncSamples([
      VehicleSample(
        key: 'P1',
        position: const ll.LatLng(44.8000, 20.5100),
        line: '79',
        type: VehicleType.bus,
        path: path,
      ),
    ], 0);
    final outboundDist = animator.trackFor('P1')!.toDist;

    // It reaches the far end and starts back west on the return leg. Each return
    // fix is geometrically as close to the outbound leg as to the return leg,
    // but must be matched to the return leg (monotonically increasing distance).
    for (final lon in [20.5200, 20.5150, 20.5100, 20.5050]) {
      animator.syncSamples([
        VehicleSample(
          key: 'P1',
          position: ll.LatLng(44.8003, lon),
          line: '79',
          type: VehicleType.bus,
          path: path,
        ),
      ], 1.0);
    }
    // On the return leg the distance-along is well past the outbound midpoint —
    // it did NOT snap back onto the outbound leg.
    expect(animator.trackFor('P1')!.toDist, greaterThan(outboundDist * 2));
  });

  test('flags a vehicle as stuck only after it sits still for a couple of minutes', () {
    var now = DateTime(2026, 1, 1, 12, 0, 0);
    final animator = VehicleTrackAnimator(clock: () => now);
    // First fix: brand new, moving.
    animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 0);
    expect(animator.isStuck('P1'), isFalse);

    // 90s later, still at the same spot — a long dwell, not yet stuck.
    now = now.add(const Duration(seconds: 90));
    animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 1.0);
    expect(animator.isStuck('P1'), isFalse);

    // Past two minutes without real movement — now it reads as stuck.
    now = now.add(const Duration(seconds: 60));
    expect(animator.isStuck('P1'), isTrue);

    // It moves again → back to moving.
    animator.sync([_arrival(garageNo: 'P1', lat: 44.82, lon: 20.52)], 1.0);
    expect(animator.isStuck('P1'), isFalse);
  });

  test('a burst of extra refreshes does not make a still vehicle read as stuck early', () {
    var now = DateTime(2026, 1, 1, 12, 0, 0);
    final animator = VehicleTrackAnimator(clock: () => now);
    animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 0);
    // Ten quick refreshes over 20s (e.g. from panning) at the same spot.
    for (var i = 0; i < 10; i++) {
      now = now.add(const Duration(seconds: 2));
      animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 1.0);
    }
    // Only ~20s of stillness — must not be flagged stuck.
    expect(animator.isStuck('P1'), isFalse);
  });

  test('caps a teleport-sized jump so the marker never races past a plausible speed', () {
    // A straight ~4 km west-east route.
    final path = RoutePath.fromLatLon([
      [44.80, 20.50],
      [44.80, 20.55],
    ]);
    final animator = VehicleTrackAnimator();
    animator.syncSamples([
      VehicleSample(
        key: 'P1',
        position: const ll.LatLng(44.80, 20.50),
        line: '2',
        type: VehicleType.tram,
        path: path,
      ),
    ], 0);
    // Next fix jumps ~1.5 km along the route in one update — implausible for 30s.
    animator.syncSamples([
      VehicleSample(
        key: 'P1',
        position: const ll.LatLng(44.80, 20.52),
        line: '2',
        type: VehicleType.tram,
        path: path,
      ),
    ], 1.0);
    // The displayed target is capped ~500 m along, well short of the ~1.5 km fix,
    // so the marker lags rather than teleporting.
    final track = animator.trackFor('P1')!;
    expect(track.toDist, lessThan(700));
    expect(track.toDist, greaterThan(300));
  });

  test('carries the line and type onto the track', () {
    final animator = VehicleTrackAnimator();
    animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 0);
    final track = animator.trackFor('P1');
    expect(track?.line, '79');
    expect(track?.type, VehicleType.bus);
  });

  group('hasPendingMotion (idle = zero frames)', () {
    test('is false for a brand-new, not-yet-moved vehicle', () {
      final animator = VehicleTrackAnimator();
      animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 0);
      // from == to on the first fix — nothing to ease, so nothing to animate.
      expect(animator.hasPendingMotion, isFalse);
    });

    test('is false when a fix lands on (essentially) the same spot', () {
      final animator = VehicleTrackAnimator();
      animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 1.0);
      animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 1.0);
      expect(animator.hasPendingMotion, isFalse);
    });

    test('is true while a real move is still easing, false once it settles', () {
      final animator = VehicleTrackAnimator();
      animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 1.0);
      // A fresh fix further along — now there's a leg to play out.
      animator.sync([_arrival(garageNo: 'P1', lat: 44.81, lon: 20.51)], 0);
      expect(animator.hasPendingMotion, isTrue);

      // A resync taken at the end of the ease (t=1): current spot == target,
      // so there's no motion left and the layer can go idle.
      animator.sync([_arrival(garageNo: 'P1', lat: 44.81, lon: 20.51)], 1.0);
      expect(animator.hasPendingMotion, isFalse);
    });

    test('detects motion along a route path', () {
      final path = RoutePath.fromLatLon([
        [44.80, 20.50],
        [44.80, 20.55],
      ]);
      final animator = VehicleTrackAnimator();
      animator.syncSamples([
        VehicleSample(
          key: 'P1',
          position: const ll.LatLng(44.80, 20.50),
          line: '2',
          type: VehicleType.tram,
          path: path,
        ),
      ], 0);
      expect(animator.hasPendingMotion, isFalse);

      // Move ~150 m along the route — a leg to ease, so motion is pending.
      animator.syncSamples([
        VehicleSample(
          key: 'P1',
          position: const ll.LatLng(44.80, 20.502),
          line: '2',
          type: VehicleType.tram,
          path: path,
        ),
      ], 1.0);
      expect(animator.hasPendingMotion, isTrue);
    });
  });

  group('shiftClock (discount time spent backgrounded)', () {
    test('a dwell spanning a hidden tab does not read as stuck on resume', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final animator = VehicleTrackAnimator(clock: () => now);
      animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 0);
      expect(animator.isStuck('P1'), isFalse);

      // The tab is hidden for 10 minutes (no ticks, no polling), then resumes.
      const hidden = Duration(minutes: 10);
      now = now.add(hidden);
      // Without discounting the frozen span the vehicle would now read stuck.
      expect(animator.isStuck('P1'), isTrue);

      // Resume shifts the "last moved" mark forward by the hidden span, so it's
      // treated as if no stall-time elapsed while the app was away.
      animator.shiftClock(hidden);
      expect(animator.isStuck('P1'), isFalse);
    });

    test('a genuine stall still trips after the shift', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final animator = VehicleTrackAnimator(clock: () => now);
      animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 0);

      now = now.add(const Duration(minutes: 5));
      animator.shiftClock(const Duration(minutes: 5)); // was hidden the whole time
      expect(animator.isStuck('P1'), isFalse);

      // Now it sits still, foreground, for over two more minutes → stuck.
      now = now.add(const Duration(minutes: 3));
      expect(animator.isStuck('P1'), isTrue);
    });

    test('ignores a non-positive shift', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final animator = VehicleTrackAnimator(clock: () => now);
      animator.sync([_arrival(garageNo: 'P1', lat: 44.80, lon: 20.50)], 0);
      final before = animator.trackFor('P1')!.lastMovedAt;
      animator.shiftClock(Duration.zero);
      expect(animator.trackFor('P1')!.lastMovedAt, before);
    });
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
