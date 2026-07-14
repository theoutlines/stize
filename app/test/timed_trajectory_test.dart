import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'package:stigla/core/route_path.dart';
import 'package:stigla/core/timed_trajectory.dart';
import 'package:stigla/core/vehicle_track_animator.dart';
import 'package:stigla/domain/models/trajectory_point.dart';
import 'package:stigla/domain/models/vehicle_type.dart';

// A straight route heading due east along lat 44.80, lon 20.50 -> 20.60. On it,
// distance-along grows monotonically with longitude, so tests reason about
// forward motion simply as "longitude increases".
RoutePath _eastRoute() => RoutePath.fromLatLon([
      [44.80, 20.50],
      [44.80, 20.60],
    ])!;

// A realistic plan (all on the east route): ~237 m station steps. The marker
// does NOT play this all the way by wall-clock — it sits at the fix and only
// leads a short ~15 s bridge, advancing further only when a fresh fix lands.
List<TrajectoryPoint> _eastPlan() => const [
      TrajectoryPoint(44.80, 20.500, 0),
      TrajectoryPoint(44.80, 20.503, 28),
      TrajectoryPoint(44.80, 20.506, 55),
    ];

final _t0 = DateTime(2026, 1, 1, 12, 0, 0);

void main() {
  group('TimedTrajectory (pure model)', () {
    test('appears AT the real fix, never flown ahead — even with a stale as_of', () {
      // Fresh: sits on the GPS point (plan point 0), not the now-as_of position.
      final fresh = TimedTrajectory.build(
        path: _eastRoute(),
        plan: _eastPlan(),
        asOf: _t0,
        now: _t0,
      )!;
      expect(fresh.position.longitude, closeTo(20.500, 1e-4));

      // Built with an already-stale board (90 s old, upstream frozen): STILL on
      // the GPS point — no fly-in / catch-up from the rotten anchor. This is the
      // core fix for "appears far ahead and flies".
      final stale = TimedTrajectory.build(
        path: _eastRoute(),
        plan: _eastPlan(),
        asOf: _t0,
        now: _t0.add(const Duration(seconds: 90)),
      )!;
      expect(stale.position.longitude, closeTo(20.500, 1e-4));
      expect(stale.hasForwardMotion(_t0.add(const Duration(seconds: 90))),
          isFalse);
    });

    test('leads only a short bridge past the fix, then holds (no fly to the end)', () {
      final tt = TimedTrajectory.build(
        path: _eastRoute(),
        plan: _eastPlan(),
        asOf: _t0,
        now: _t0,
      )!;
      // Moves a little forward within the bridge window.
      tt.advance(_t0.add(const Duration(seconds: 5)));
      expect(tt.position.longitude, greaterThan(20.500));

      // Well past the bridge, still fresh (< staleness): holds a short lead — it
      // does NOT keep sliding to the plan's far end (20.506).
      tt.advance(_t0.add(const Duration(seconds: 40)));
      final held = tt.position.longitude;
      expect(held, greaterThan(20.500));
      expect(held, lessThan(20.5025)); // ~15 s of ~4 m/s ≈ a couple hundred metres
    });

    test('a stale fix stops predicting: holds near the fix and idles', () {
      final tt = TimedTrajectory.build(
        path: _eastRoute(),
        plan: _eastPlan(),
        asOf: _t0,
        now: _t0,
      )!;
      tt.advance(_t0.add(const Duration(seconds: 15))); // bridge in
      final bridged = tt.position.longitude;
      // Board goes stale (no fresh fix) — must NOT coast on toward the plan end.
      tt.advance(_t0.add(const Duration(seconds: 300)));
      expect(tt.position.longitude, closeTo(bridged, 2e-3));
      expect(tt.hasForwardMotion(_t0.add(const Duration(seconds: 300))), isFalse);
      // It certainly never flew to the plan's far end.
      expect(tt.position.longitude, lessThan(20.505));
    });

    test('a fresh fix drives progress forward and never rewinds', () {
      final route = _eastRoute();
      final tt = TimedTrajectory.build(
        path: route,
        plan: _eastPlan(),
        asOf: _t0,
        now: _t0,
      )!;
      tt.advance(_t0.add(const Duration(seconds: 15)));
      final before = tt.position.longitude;

      // 30 s later a fresh fix says the vehicle actually reached lon 20.505.
      final now = _t0.add(const Duration(seconds: 30));
      tt.updatePlan(
        path: route,
        plan: const [
          TrajectoryPoint(44.80, 20.505, 0),
          TrajectoryPoint(44.80, 20.508, 30),
        ],
        asOf: now,
        now: now,
      );
      final lons = <double>[before];
      for (var s = 0; s <= 30; s += 5) {
        tt.advance(now.add(Duration(seconds: s)));
        lons.add(tt.position.longitude);
      }
      // Monotonic non-decreasing (no snap-back) and it progressed forward.
      for (var i = 1; i < lons.length; i++) {
        expect(lons[i], greaterThanOrEqualTo(lons[i - 1] - 1e-9),
            reason: 'moved backward: $lons');
      }
      expect(lons.last, greaterThan(before));
    });

    test('a fresh plan placing the vehicle behind never rewinds the marker', () {
      final route = _eastRoute();
      final tt = TimedTrajectory.build(
        path: route,
        plan: _eastPlan(),
        asOf: _t0,
        now: _t0,
      )!;
      tt.advance(_t0.add(const Duration(seconds: 15)));
      final before = tt.position.longitude;
      // A fresh fix that puts the vehicle back at the origin (recalculated): the
      // marker holds, never jumps backward.
      final now = _t0.add(const Duration(seconds: 30));
      tt.updatePlan(path: route, plan: _eastPlan(), asOf: now, now: now);
      for (var s = 0; s <= 30; s += 10) {
        tt.advance(now.add(Duration(seconds: s)));
        expect(tt.position.longitude, greaterThanOrEqualTo(before - 1e-9));
      }
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
      tt.advance(_t0.add(const Duration(seconds: 15)));
      final before = tt.position.longitude;
      expect(before, greaterThan(20.500));

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
        now: _t0.add(const Duration(seconds: 15)),
      );
      expect(tt.position.longitude, closeTo(before, 5e-3));
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

    test('appears at the fix, leads a short bridge, idles stale near the fix', () {
      var now = _t0;
      final animator = VehicleTrackAnimator(clock: () => now);
      animator.syncSamples([sample('P1', asOf: _t0)], 0, now: now);
      // Appears on the GPS point, not flown ahead.
      expect(animator.positionOf('P1', 0).longitude, closeTo(20.500, 1e-4));

      // A few seconds later there's forward motion to render (the bridge).
      now = _t0.add(const Duration(seconds: 5));
      expect(animator.hasPendingMotion, isTrue);
      animator.advanceTimed(now);
      final mid = animator.positionOf('P1', 0);
      expect(mid.longitude, greaterThan(20.500));
      expect(mid.longitude, lessThan(20.503)); // a short lead, not a fly
      expect(animator.headingAt('P1', 0)!, closeTo(90, 5));

      // Stale (no fresh fix): parked near the fix, nothing left to animate — and
      // NOT slid to the plan's far end.
      now = _t0.add(const Duration(seconds: 300));
      animator.advanceTimed(now);
      expect(animator.hasPendingMotion, isFalse);
      expect(animator.positionOf('P1', 0).longitude, lessThan(20.504));
    });

    test('a fresh fix drives the marker forward without rewinding', () {
      var now = _t0;
      final animator = VehicleTrackAnimator(clock: () => now);
      animator.syncSamples([sample('P1', asOf: _t0)], 0, now: now);
      now = _t0.add(const Duration(seconds: 15));
      animator.advanceTimed(now);
      final before = animator.positionOf('P1', 0).longitude;

      // Fresh fix anchored at now.
      animator.syncSamples([sample('P1', asOf: now)], 0, now: now);
      for (var s = 0; s <= 30; s += 10) {
        final t = now.add(Duration(seconds: s));
        animator.advanceTimed(t);
        expect(animator.positionOf('P1', 0).longitude,
            greaterThanOrEqualTo(before - 1e-9));
      }
    });

    test('falls back to the conservative ease when no plan is supplied', () {
      final animator = VehicleTrackAnimator();
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
      final half = animator.positionOf('P1', 0.5).longitude;
      expect(half, greaterThan(20.50));
      expect(half, lessThan(20.51));
    });

    test('extrapolates along the plan when no route path is available yet', () {
      var now = _t0;
      final animator = VehicleTrackAnimator(clock: () => now);
      // No GTFS shape yet — the plan alone still drives the vehicle (along its own
      // station points) rather than standing at its fix.
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
      // Fresh: there's a bridge of motion to render, and it moves forward.
      now = _t0.add(const Duration(seconds: 5));
      expect(animator.hasMotion('P1'), isTrue);
      animator.advanceTimed(now);
      expect(animator.positionOf('P1', 0).longitude, greaterThan(20.500));
    });

    test('abandons timed mode (without rewinding) if the plan later drops out', () {
      var now = _t0;
      final animator = VehicleTrackAnimator(clock: () => now);
      animator.syncSamples([sample('P1', asOf: _t0)], 0, now: now);
      now = _t0.add(const Duration(seconds: 15));
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
      // Resumes conservative easing from where it visually was — no snap back.
      expect(animator.positionOf('P1', 0).longitude, closeTo(before, 1e-3));
    });
  });
}
