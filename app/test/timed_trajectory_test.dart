import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:stigla/core/route_path.dart';
import 'package:stigla/core/timed_trajectory.dart';
import 'package:stigla/core/vehicle_track_animator.dart';
import 'package:stigla/domain/models/trajectory_point.dart';
import 'package:stigla/domain/models/vehicle_type.dart';

// A straight route heading due east along lat 44.80, lon 20.50 -> 20.60. On it,
// distance-along grows monotonically with longitude, so tests can reason about
// forward motion simply as "longitude increases".
RoutePath _eastRoute() => RoutePath.fromLatLon([
      [44.80, 20.50],
      [44.80, 20.60],
    ])!;

// A plan (all on the east route) placing the vehicle at lon 20.50 now, 20.55 at
// +100s, 20.60 at +200s.
List<TrajectoryPoint> _eastPlan() => const [
      TrajectoryPoint(44.80, 20.50, 0),
      TrajectoryPoint(44.80, 20.55, 100),
      TrajectoryPoint(44.80, 20.60, 200),
    ];

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
      expect(tt.position.longitude, closeTo(20.50, 1e-4));

      // Halfway through the first leg (+50s) it's around lon 20.525.
      tt.advance(_t0.add(const Duration(seconds: 50)));
      expect(tt.position.longitude, greaterThan(20.50));
      expect(tt.position.longitude, lessThan(20.55));

      // At the second waypoint's eta (+100s) it's reached ~lon 20.55.
      tt.advance(_t0.add(const Duration(seconds: 100)));
      expect(tt.position.longitude, closeTo(20.55, 3e-3));
    });

    test('never runs past the end of the plan', () {
      final tt = TimedTrajectory.build(
        path: _eastRoute(),
        plan: _eastPlan(),
        asOf: _t0,
        now: _t0,
      )!;
      // Way past the plan horizon.
      tt.advance(_t0.add(const Duration(seconds: 500)));
      expect(tt.position.longitude, closeTo(20.60, 1e-4));
      expect(tt.displayDistance, closeTo(tt.endDistance, 0.01));

      // Advancing further never pushes it beyond the last waypoint.
      tt.advance(_t0.add(const Duration(seconds: 900)));
      expect(tt.displayDistance, closeTo(tt.endDistance, 0.01));
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

    test('a fresher plan that recalculates ETAs longer never rewinds the marker', () {
      final route = _eastRoute();
      final tt = TimedTrajectory.build(
        path: route,
        plan: _eastPlan(),
        asOf: _t0,
        now: _t0,
      )!;
      // Play forward to ~lon 20.55.
      tt.advance(_t0.add(const Duration(seconds: 100)));
      final before = tt.position.longitude;
      expect(before, closeTo(20.55, 5e-3));

      // A fresh plan (as-of now) says the vehicle is actually back at lon 20.50
      // and only reaches 20.55 in another 100s — i.e. it's *behind* where the
      // marker shows. The marker must hold, never jump backward.
      final now = _t0.add(const Duration(seconds: 100));
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
      // Marker is near the start (lon ~20.50).
      expect(tt.position.longitude, closeTo(20.50, 1e-3));

      // A fresh plan says the vehicle is already at lon 20.58 now (moved faster
      // than predicted). One short frame later it should have advanced toward it
      // but NOT jumped all the way — smooth convergence.
      tt.updatePlan(
        path: route,
        plan: const [
          TrajectoryPoint(44.80, 20.58, 0),
          TrajectoryPoint(44.80, 20.60, 100),
        ],
        asOf: _t0,
        now: _t0,
      );
      tt.advance(_t0.add(const Duration(milliseconds: 500)));
      final afterOneFrame = tt.position.longitude;
      expect(afterOneFrame, greaterThan(20.50)); // moved forward
      expect(afterOneFrame, lessThan(20.58)); // but did not teleport to target

      // Given enough time it does reach it.
      tt.advance(_t0.add(const Duration(seconds: 20)));
      expect(tt.position.longitude, closeTo(20.58, 5e-3));
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
        [44.80, 20.50],
        [44.80, 20.60],
      ])!;
      const plan = [
        TrajectoryPoint(44.80, 20.50, 0),
        TrajectoryPoint(44.80, 20.60, 100),
      ];
      final tt = TimedTrajectory.build(
        path: chord,
        plan: plan,
        asOf: _t0,
        now: _t0,
      )!;
      tt.advance(_t0.add(const Duration(seconds: 50)));
      final before = tt.position.longitude;
      expect(before, closeTo(20.55, 2e-2));

      // The road shape arrives (denser vertices, same line). Upgrading the
      // geometry must re-anchor at the same geographic spot — NOT reset to the
      // route origin (which a raw distance-along on a different path would do).
      final road = RoutePath.fromLatLon([
        [44.80, 20.50],
        [44.80, 20.53],
        [44.80, 20.57],
        [44.80, 20.60],
      ])!;
      tt.updatePlan(
        path: road,
        plan: plan,
        asOf: _t0,
        now: _t0.add(const Duration(seconds: 50)),
      );
      expect(tt.position.longitude, closeTo(before, 5e-3));
      // And keeps moving forward from there.
      tt.advance(_t0.add(const Duration(seconds: 70)));
      expect(tt.position.longitude, greaterThan(before));
    });
  });

  group('VehicleTrackAnimator timed mode', () {
    VehicleSample sample(String key, {required DateTime asOf, DateTime? now}) {
      return VehicleSample(
        key: key,
        position: const ll.LatLng(44.80, 20.50),
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
      now = _t0.add(const Duration(seconds: 50));
      animator.advanceTimed(now);
      final mid = animator.positionOf('P1', 0);
      expect(mid.longitude, greaterThan(20.50));
      expect(animator.hasPendingMotion, isTrue);
      // Heading comes from the route tangent (due east ≈ 90°).
      expect(animator.headingAt('P1', 0)!, closeTo(90, 5));

      // Past the plan's horizon: parked at the end, nothing left to animate.
      now = _t0.add(const Duration(seconds: 300));
      animator.advanceTimed(now);
      expect(animator.positionOf('P1', 0).longitude, closeTo(20.60, 1e-3));
      expect(animator.hasPendingMotion, isFalse);
    });

    test('a fresh plan never rewinds the marker across syncs', () {
      var now = _t0;
      final animator = VehicleTrackAnimator(clock: () => now);
      animator.syncSamples([sample('P1', asOf: _t0)], 0, now: now);
      now = _t0.add(const Duration(seconds: 100));
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
          position: const ll.LatLng(44.80, 20.50),
          line: '2',
          type: VehicleType.tram,
          path: null,
          trajectory: _eastPlan(),
          asOf: _t0,
        ),
      ], 0, now: now);
      expect(animator.trackFor('P1')!.timed, isNotNull);
      now = _t0.add(const Duration(seconds: 100));
      animator.advanceTimed(now);
      expect(animator.positionOf('P1', 0).longitude, greaterThan(20.50));
      expect(animator.hasMotion('P1'), isTrue);
    });

    test('abandons timed mode (without rewinding) if the plan later drops out', () {
      var now = _t0;
      final animator = VehicleTrackAnimator(clock: () => now);
      animator.syncSamples([sample('P1', asOf: _t0)], 0, now: now);
      now = _t0.add(const Duration(seconds: 100));
      animator.advanceTimed(now);
      final before = animator.positionOf('P1', 0).longitude;

      // Next sync carries no plan (feature flipped off / plan gone).
      animator.syncSamples([
        VehicleSample(
          key: 'P1',
          position: const ll.LatLng(44.80, 20.55),
          line: '2',
          type: VehicleType.tram,
          path: _eastRoute(),
        ),
      ], 0, now: now);
      expect(animator.trackFor('P1')!.timed, isNull);
      // The marker resumes conservative easing from where it visually was — it
      // does not snap back to the route origin.
      expect(animator.positionOf('P1', 0).longitude,
          closeTo(before, 1e-3));
    });
  });
}
