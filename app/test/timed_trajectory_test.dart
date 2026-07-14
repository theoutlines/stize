import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:stigla/core/route_path.dart';
import 'package:stigla/core/timed_trajectory.dart';
import 'package:stigla/core/vehicle_track_animator.dart';
import 'package:stigla/domain/models/trajectory_point.dart';
import 'package:stigla/domain/models/vehicle_type.dart';

// A straight route heading due east along lat 44.80, lon 20.50 -> 20.60. On it,
// distance-along grows monotonically with longitude, so tests can reason about
// forward motion simply as "longitude increases". Long enough that the restraint
// caps (500 m ahead) have headroom.
RoutePath _eastRoute() => RoutePath.fromLatLon([
      [44.80, 20.50],
      [44.80, 20.60],
    ])!;

// A realistic plan (all on the east route): ~237 m station steps spanning 55 s —
// comfortably inside the restrained-extrapolation window (60 s / 500 m), so the
// forward/converge/no-rewind behaviour is what these tests exercise. The caps
// themselves have their own dedicated test.
List<TrajectoryPoint> _eastPlan() => const [
      TrajectoryPoint(44.80, 20.500, 0),
      TrajectoryPoint(44.80, 20.503, 28),
      TrajectoryPoint(44.80, 20.506, 55),
    ];

const _distance = ll.Distance();
final _t0 = DateTime(2026, 1, 1, 12, 0, 0);

void main() {
  group('TimedTrajectory (pure model)', () {
    test('starts at the current position and plays forward by wall-clock time', () {
      final tt = TimedTrajectory.build(
        path: _eastRoute(),
        plan: _eastPlan(),
        asOf: _t0,
        now: _t0,
      )!;
      // At as-of time the marker sits at the plan's first point.
      expect(tt.position.longitude, closeTo(20.500, 1e-4));

      // Part-way along (+28 s, the middle waypoint) it has moved east.
      tt.advance(_t0.add(const Duration(seconds: 28)));
      expect(tt.position.longitude, greaterThan(20.500));
      expect(tt.position.longitude, lessThan(20.506));

      // At the last waypoint's eta (+55 s) it's reached ~lon 20.506.
      tt.advance(_t0.add(const Duration(seconds: 55)));
      expect(tt.position.longitude, closeTo(20.506, 5e-4));
    });

    test('never runs past the end of the plan', () {
      final tt = TimedTrajectory.build(
        path: _eastRoute(),
        plan: _eastPlan(),
        asOf: _t0,
        now: _t0,
      )!;
      // Way past the plan horizon: parked at the plan's end (also the restraint
      // horizon here, since the plan is < 500 m long).
      tt.advance(_t0.add(const Duration(seconds: 500)));
      expect(tt.position.longitude, closeTo(20.506, 1e-3));
      expect(tt.displayDistance, closeTo(tt.endDistance, 0.5));

      // Advancing further never pushes it beyond the last waypoint.
      tt.advance(_t0.add(const Duration(seconds: 900)));
      expect(tt.displayDistance, closeTo(tt.endDistance, 0.5));
    });

    test('hasForwardMotion is false once the plan is exhausted (idle)', () {
      final tt = TimedTrajectory.build(
        path: _eastRoute(),
        plan: _eastPlan(),
        asOf: _t0,
        now: _t0,
      )!;
      expect(tt.hasForwardMotion(_t0.add(const Duration(seconds: 30))), isTrue);
      // Reached the end → nothing left to render.
      tt.advance(_t0.add(const Duration(seconds: 300)));
      expect(tt.hasForwardMotion(_t0.add(const Duration(seconds: 300))), isFalse);
    });

    test('restrains extrapolation: caps how far it predicts past the last fix', () {
      // A plan that, unchecked, would carry the vehicle kilometres away over ten
      // minutes. With no fresh fix arriving, the marker must lead only modestly
      // and then hold — not run away / let the map live its own life.
      final route = RoutePath.fromLatLon([
        [44.80, 20.50],
        [44.80, 20.90],
      ])!;
      const farPlan = [
        TrajectoryPoint(44.80, 20.50, 0),
        TrajectoryPoint(44.80, 20.60, 600),
      ];
      final tt = TimedTrajectory.build(
        path: route,
        plan: farPlan,
        asOf: _t0,
        now: _t0,
      )!;
      final start = tt.position;
      for (var s = 0; s <= 200; s += 5) {
        tt.advance(_t0.add(Duration(seconds: s)));
      }
      // Stopped predicting once the look-ahead window passed with no fresh data…
      expect(tt.hasForwardMotion(_t0.add(const Duration(seconds: 200))), isFalse);
      // …and it led forward but did NOT run away — capped ~500 m ahead.
      final aheadM = _distance.as(ll.LengthUnit.Meter, start, tt.position);
      expect(aheadM, greaterThan(100));
      expect(aheadM, lessThan(600));
    });

    test('a fresher plan that recalculates ETAs longer never rewinds the marker', () {
      final route = _eastRoute();
      final tt = TimedTrajectory.build(
        path: route,
        plan: _eastPlan(),
        asOf: _t0,
        now: _t0,
      )!;
      // Play forward to ~lon 20.506 (plan end).
      tt.advance(_t0.add(const Duration(seconds: 60)));
      final before = tt.position.longitude;
      expect(before, closeTo(20.506, 5e-3));

      // A fresh plan (as-of now) says the vehicle is actually back at lon 20.500
      // — i.e. behind where the marker shows. The marker must hold, never jump
      // backward.
      final now = _t0.add(const Duration(seconds: 60));
      tt.updatePlan(path: route, plan: _eastPlan(), asOf: now, now: now);
      final lons = <double>[before];
      for (var s = 0; s <= 60; s += 10) {
        tt.advance(now.add(Duration(seconds: s)));
        lons.add(tt.position.longitude);
      }
      // Monotonic non-decreasing throughout — no snap-back.
      for (var i = 1; i < lons.length; i++) {
        expect(lons[i], greaterThanOrEqualTo(lons[i - 1] - 1e-9),
            reason: 'marker moved backward: $lons');
      }
    });

    test('a fresher plan with the vehicle ahead converges smoothly, not by teleport', () {
      final route = _eastRoute();
      final tt = TimedTrajectory.build(
        path: route,
        plan: _eastPlan(),
        asOf: _t0,
        now: _t0,
      )!;
      // Marker is near the start (lon ~20.500).
      expect(tt.position.longitude, closeTo(20.500, 1e-3));

      // A fresh plan says the vehicle is already at lon 20.503 now (moved faster
      // than predicted) — within the restraint window. One short frame later it
      // should have advanced toward it but NOT jumped all the way.
      tt.updatePlan(
        path: route,
        plan: const [
          TrajectoryPoint(44.80, 20.503, 0),
          TrajectoryPoint(44.80, 20.506, 60),
        ],
        asOf: _t0,
        now: _t0,
      );
      tt.advance(_t0.add(const Duration(milliseconds: 500)));
      final afterOneFrame = tt.position.longitude;
      expect(afterOneFrame, greaterThan(20.500)); // moved forward
      expect(afterOneFrame, lessThan(20.503)); // but did not teleport to target

      // Given enough time it reaches and passes the fresh start.
      tt.advance(_t0.add(const Duration(seconds: 40)));
      expect(tt.position.longitude, greaterThan(20.503));
      expect(tt.position.longitude, lessThan(20.507));
    });

    test('build returns null without a usable path or ≥2 forward points', () {
      expect(
        TimedTrajectory.build(
          path: _eastRoute(),
          plan: const [TrajectoryPoint(44.80, 20.50, 0)],
          asOf: _t0,
          now: _t0,
        ),
        isNull,
      );
    });

    test('upgrading to a refined geometry re-anchors at the same spot', () {
      // Start on the plan's own straight chord (no road shape loaded yet).
      final chord = RoutePath.fromLatLon([
        [44.80, 20.500],
        [44.80, 20.506],
      ])!;
      const plan = [
        TrajectoryPoint(44.80, 20.500, 0),
        TrajectoryPoint(44.80, 20.506, 55),
      ];
      final tt = TimedTrajectory.build(
        path: chord,
        plan: plan,
        asOf: _t0,
        now: _t0,
      )!;
      tt.advance(_t0.add(const Duration(seconds: 28)));
      final before = tt.position.longitude;
      expect(before, closeTo(20.503, 5e-3));

      // The road shape arrives (denser vertices, same line). Upgrading the
      // geometry must re-anchor at the same geographic spot — NOT reset to the
      // route origin (which a raw distance-along on a different path would do).
      final road = RoutePath.fromLatLon([
        [44.80, 20.500],
        [44.80, 20.502],
        [44.80, 20.504],
        [44.80, 20.506],
      ])!;
      tt.updatePlan(
        path: road,
        plan: plan,
        asOf: _t0,
        now: _t0.add(const Duration(seconds: 28)),
      );
      expect(tt.position.longitude, closeTo(before, 5e-3));
      // And keeps moving forward from there.
      tt.advance(_t0.add(const Duration(seconds: 45)));
      expect(tt.position.longitude, greaterThan(before));
    });
  });

  group('VehicleTrackAnimator timed mode', () {
    VehicleSample sample(String key, {required DateTime asOf, DateTime? now}) {
      return VehicleSample(
        key: key,
        position: const ll.LatLng(44.80, 20.500),
        line: '2',
        type: VehicleType.tram,
        path: _eastRoute(),
        trajectory: _eastPlan(),
        asOf: asOf,
      );
    }

    test('plays the plan forward and reports pending motion, then idles at the end', () {
      var now = _t0;
      final animator = VehicleTrackAnimator(clock: () => now);
      animator.syncSamples([sample('P1', asOf: _t0)], 0, now: now);

      // Mid-plan: advancing the clock moves the marker east and keeps it live.
      now = _t0.add(const Duration(seconds: 40));
      animator.advanceTimed(now);
      final mid = animator.positionOf('P1', 0);
      expect(mid.longitude, greaterThan(20.500));
      expect(animator.hasPendingMotion, isTrue);
      // Heading comes from the route tangent (due east ≈ 90°).
      expect(animator.headingAt('P1', 0)!, closeTo(90, 5));

      // Past the plan's horizon: parked at the end, nothing left to animate.
      now = _t0.add(const Duration(seconds: 300));
      animator.advanceTimed(now);
      expect(animator.positionOf('P1', 0).longitude, closeTo(20.506, 1e-3));
      expect(animator.hasPendingMotion, isFalse);
    });

    test('a fresh plan never rewinds the marker across syncs', () {
      var now = _t0;
      final animator = VehicleTrackAnimator(clock: () => now);
      animator.syncSamples([sample('P1', asOf: _t0)], 0, now: now);
      now = _t0.add(const Duration(seconds: 60));
      animator.advanceTimed(now);
      final before = animator.positionOf('P1', 0).longitude;

      // Fresh plan anchored at now, resetting the vehicle back to the origin.
      animator.syncSamples([sample('P1', asOf: now)], 0, now: now);
      for (var s = 0; s <= 60; s += 15) {
        final t = now.add(Duration(seconds: s));
        animator.advanceTimed(t);
        expect(animator.positionOf('P1', 0).longitude,
            greaterThanOrEqualTo(before - 1e-9));
      }
    });

    test('falls back to the conservative ease when no plan is supplied', () {
      final animator = VehicleTrackAnimator();
      // No trajectory/asOf → timed mode stays off; the marker eases from/to.
      animator.syncSamples([
        VehicleSample(
          key: 'P1',
          position: const ll.LatLng(44.80, 20.50),
          line: '2',
          type: VehicleType.tram,
          path: _eastRoute(),
        ),
      ], 0);
      animator.syncSamples([
        VehicleSample(
          key: 'P1',
          position: const ll.LatLng(44.80, 20.51),
          line: '2',
          type: VehicleType.tram,
          path: _eastRoute(),
        ),
      ], 1.0);
      expect(animator.trackFor('P1')!.timed, isNull);
      // Interpolates on the animation value t, not wall-clock.
      final half = animator.positionOf('P1', 0.5).longitude;
      expect(half, greaterThan(20.50));
      expect(half, lessThan(20.51));
    });

    test('extrapolates along the plan when no route path is available yet', () {
      var now = _t0;
      final animator = VehicleTrackAnimator(clock: () => now);
      // No GTFS shape yet — but the plan alone drives the vehicle forward (along
      // its own station points) instead of standing at its fix. This is the
      // "keep predicting when fixes/geometry run out" fix, not a standstill.
      animator.syncSamples([
        VehicleSample(
          key: 'P1',
          position: const ll.LatLng(44.80, 20.500),
          line: '2',
          type: VehicleType.tram,
          path: null,
          trajectory: _eastPlan(),
          asOf: _t0,
        ),
      ], 0, now: now);
      expect(animator.trackFor('P1')!.timed, isNotNull);
      now = _t0.add(const Duration(seconds: 30));
      animator.advanceTimed(now);
      expect(animator.positionOf('P1', 0).longitude, greaterThan(20.500));
      expect(animator.hasMotion('P1'), isTrue);
    });

    test('abandons timed mode (without rewinding) if the plan later drops out', () {
      var now = _t0;
      final animator = VehicleTrackAnimator(clock: () => now);
      animator.syncSamples([sample('P1', asOf: _t0)], 0, now: now);
      now = _t0.add(const Duration(seconds: 60));
      animator.advanceTimed(now);
      final before = animator.positionOf('P1', 0).longitude;

      // Next sync carries no plan (feature flipped off / plan gone).
      animator.syncSamples([
        VehicleSample(
          key: 'P1',
          position: const ll.LatLng(44.80, 20.506),
          line: '2',
          type: VehicleType.tram,
          path: _eastRoute(),
        ),
      ], 0, now: now);
      expect(animator.trackFor('P1')!.timed, isNull);
      // The marker resumes conservative easing from where it visually was — it
      // does not snap back to the route origin.
      expect(animator.positionOf('P1', 0).longitude, closeTo(before, 1e-3));
    });
  });
}
