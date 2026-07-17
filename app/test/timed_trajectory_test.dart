import 'dart:math' as math;

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
// plays this forward by wall-clock *continuously while the fix is fresh* (up to
// the staleness gate at 45 s), so it keeps moving across the whole 30 s poll
// interval instead of sitting after a short bridge. Once the fix ages past the
// gate the target collapses back to the fix and it holds (never flies to the
// plan's far end).
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

    test('appears mid-interval at the predicted-now spot, not the stale fix', () {
      // Built 20 s into the interval (fresh, < gate): shows up where the vehicle
      // actually is now (plan[20s] ≈ 20.502), not back at the 20 s-old GPS point
      // — so it doesn't race forward to catch up on appearance.
      final tt = TimedTrajectory.build(
        path: _eastRoute(),
        plan: _eastPlan(),
        asOf: _t0,
        now: _t0.add(const Duration(seconds: 20)),
      )!;
      expect(tt.position.longitude, greaterThan(20.5015));
      expect(tt.position.longitude, lessThan(20.503));
    });

    test('predicts continuously across the interval while the fix is fresh', () {
      final tt = TimedTrajectory.build(
        path: _eastRoute(),
        plan: _eastPlan(),
        asOf: _t0,
        now: _t0,
      )!;
      tt.advance(_t0.add(const Duration(seconds: 5)));
      final at5 = tt.position.longitude;
      expect(at5, greaterThan(20.500));

      // Still fresh (40 s < 45 s gate): kept moving forward the WHOLE interval —
      // it did not stall at a short bridge. Near plan[40s] ≈ 20.5043.
      tt.advance(_t0.add(const Duration(seconds: 40)));
      final at40 = tt.position.longitude;
      expect(at40, greaterThan(at5 + 1e-4));
      expect(at40, closeTo(20.50433, 6e-4));
      // But never past the plan's far end (20.506).
      expect(at40, lessThan(20.506));
    });

    test('a stale fix stops predicting: holds near the fix and idles', () {
      final tt = TimedTrajectory.build(
        path: _eastRoute(),
        plan: _eastPlan(),
        asOf: _t0,
        now: _t0,
      )!;
      tt.advance(_t0.add(const Duration(seconds: 15))); // predicting, fresh
      final led = tt.position.longitude;
      // Board goes stale (no fresh fix) — must NOT coast on toward the plan end.
      tt.advance(_t0.add(const Duration(seconds: 300)));
      expect(tt.position.longitude, closeTo(led, 2e-3));
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

    test('catch-up is acceleration-limited: velocity never steps between frames', () {
      // A fresh fix ~79 m ahead (≈ one lon-milli at this latitude) — a realistic
      // poll gap, well within the closing-speed cap.
      final route = _eastRoute();
      final tt = TimedTrajectory.build(
        path: route,
        plan: const [
          TrajectoryPoint(44.80, 20.500, 0),
          TrajectoryPoint(44.80, 20.510, 120),
        ],
        asOf: _t0,
        now: _t0,
      )!;
      tt.updatePlan(
        path: route,
        plan: const [
          TrajectoryPoint(44.80, 20.501, 0),
          TrajectoryPoint(44.80, 20.511, 120),
        ],
        asOf: _t0,
        now: _t0,
      );

      // Step at a realistic frame cadence and watch the speed: it must ramp,
      // never jump — |Δv| ≤ a_max·dt (+ a hair for float error) every frame.
      const frame = Duration(milliseconds: 16);
      const dt = 16 / 1000;
      const aMax = 3.0;
      var prevV = tt.displaySpeed;
      var t = _t0;
      var maxV = 0.0;
      for (var i = 0; i < 1250; i++) {
        t = t.add(frame);
        tt.advance(t);
        final v = tt.displaySpeed;
        expect((v - prevV).abs(), lessThanOrEqualTo(aMax * dt + 1e-6),
            reason: 'velocity stepped at frame $i: $prevV → $v');
        maxV = math.max(maxV, v);
        prevV = v;
      }
      // It actually did catch up (the gap closed to ~0) within the window.
      expect(tt.catchUpGap(t), lessThan(2.0));
      // And it cruised faster than the plan speed (~6.6 m/s) to close the gap —
      // an "even" catch-up, not a single exponential spike then a crawl.
      expect(maxV, greaterThan(8.0));
    });

    test('the first catch-up frame does not lurch (eases in from rest)', () {
      final route = _eastRoute();
      final tt = TimedTrajectory.build(
        path: route,
        plan: const [
          TrajectoryPoint(44.80, 20.500, 0),
          TrajectoryPoint(44.80, 20.510, 120),
        ],
        asOf: _t0,
        now: _t0,
      )!;
      final d0 = tt.displayDistance;
      // A fresh fix ~158 m ahead appears (a large but plausible re-anchor).
      tt.updatePlan(
        path: route,
        plan: const [
          TrajectoryPoint(44.80, 20.502, 0),
          TrajectoryPoint(44.80, 20.512, 120),
        ],
        asOf: _t0,
        now: _t0,
      );
      // One 16 ms frame after the gap appears: the step is bounded by the
      // acceleration limit (½·a·dt²), not a fraction of the whole gap.
      tt.advance(_t0.add(const Duration(milliseconds: 16)));
      final firstStep = tt.displayDistance - d0;
      expect(firstStep, lessThan(0.05)); // ½·3·0.016² ≈ 0.4 mm, nowhere near a lurch
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

    test('appears at the fix, predicts continuously, idles stale near the lead', () {
      var now = _t0;
      final animator = VehicleTrackAnimator(clock: () => now);
      animator.syncSamples([sample('P1', asOf: _t0)], 0, now: now);
      // Built fresh at asOf (age 0): appears on the GPS point, not flown ahead.
      expect(animator.positionOf('P1', 0).longitude, closeTo(20.500, 1e-4));

      // A few seconds later there's forward motion to render.
      now = _t0.add(const Duration(seconds: 5));
      expect(animator.hasPendingMotion, isTrue);
      animator.advanceTimed(now);
      final at5 = animator.positionOf('P1', 0).longitude;
      expect(at5, greaterThan(20.500));
      expect(animator.headingAt('P1', 0)!, closeTo(90, 5));

      // Still fresh at 40 s: kept moving the whole interval (continuous), not
      // stalled at a short bridge.
      now = _t0.add(const Duration(seconds: 40));
      animator.advanceTimed(now);
      final at40 = animator.positionOf('P1', 0).longitude;
      expect(at40, greaterThan(at5 + 1e-4));

      // Stale (no fresh fix): parked at the lead, nothing left to animate — and
      // NOT slid to the plan's far end.
      now = _t0.add(const Duration(seconds: 300));
      animator.advanceTimed(now);
      expect(animator.hasPendingMotion, isFalse);
      expect(animator.positionOf('P1', 0).longitude, lessThan(20.506));
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
      // Fresh: there's motion to render, and it moves forward.
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

  // ---------------------------------------------------------------------------
  // Stop dwell: the shape of motion between plan waypoints.
  //
  // These reason about *distance-along* in metres via [targetDistanceAt] (the
  // plan's curve, before chase dynamics) and the marker's own rendered motion.
  // The route is the same due-east line, so distance grows with longitude.
  group('stop dwell', () {
    // A Belgrade-paced plan (~18 km/h average, the real order of magnitude):
    // ~100 m in 20 s to the first stop, then ~125 m in 25 s to the second. Both
    // stops sit inside the 45 s staleness gate, which is the only window that
    // ever renders.
    List<TrajectoryPoint> calmPlan() => const [
          TrajectoryPoint(44.80, 20.50000, 0),
          TrajectoryPoint(44.80, 20.50126, 20), // stop 1
          TrajectoryPoint(44.80, 20.50283, 45), // stop 2
        ];

    // The same route at a brisk ~30 km/h (237 m per 28 s). No profile can fit a
    // pause here without an implausible sprint, so it must degrade.
    List<TrajectoryPoint> briskPlan() => const [
          TrajectoryPoint(44.80, 20.500, 0),
          TrajectoryPoint(44.80, 20.503, 28),
          TrajectoryPoint(44.80, 20.506, 55),
        ];

    TimedTrajectory build(List<TrajectoryPoint> plan) => TimedTrajectory.build(
          path: _eastRoute(),
          plan: plan,
          asOf: _t0,
          now: _t0,
        )!;

    double targetAt(TimedTrajectory t, double seconds) => t.targetDistanceAt(
        _t0.add(Duration(milliseconds: (seconds * 1000).round())));

    // A plan whose middle station sits OFF the route line (~1 km north) — the
    // signature of a GTFS shape that doesn't cover a route variant. Its
    // projection lands ~1 km from its true position, so no dwell may happen
    // there (a pause where no stop is). The on-route stops still dwell.
    // Calm timing (dwells clearly) but the MIDDLE stop sits ~1.1 km north of the
    // route line — the signature of a shape that doesn't cover this variant.
    List<TrajectoryPoint> offShapePlan() => const [
          TrajectoryPoint(44.80, 20.50000, 0),
          TrajectoryPoint(44.81, 20.50126, 20), // stop 1: ~1.1 km NORTH, off-route
          TrajectoryPoint(44.80, 20.50283, 45), // stop 2: on the route
        ];

    test('no dwell anywhere near a station the shape does not reach', () {
      // Control: the all-on-shape calm plan DOES stand still at its stop.
      final onShape = build(calmPlan());
      final atStop = targetAt(onShape, 20);
      expect(targetAt(onShape, 21.5), closeTo(atStop, 0.6),
          reason: 'sanity: an on-shape stop must dwell');

      // Same timing but stop 1 off-shape: the marker must NOT stand still at its
      // time (~20 s) — a pause there would be ~1 km from any real stop. Sampled
      // finely so a 3 s dwell can't hide between integer seconds.
      final off = build(offShapePlan());
      var minSpeed = double.infinity;
      for (var ms = 17000; ms <= 24000; ms += 250) {
        final a = off.targetDistanceAt(_t0.add(Duration(milliseconds: ms)));
        final b = off.targetDistanceAt(_t0.add(Duration(milliseconds: ms + 250)));
        final v = (b - a) / 0.25;
        if (v < minSpeed) minSpeed = v;
      }
      expect(minSpeed, greaterThan(0.5),
          reason: 'marker dwelled at an off-shape station '
              '(min speed ${minSpeed.toStringAsFixed(2)} m/s near 20 s)');
    });

    test('the plan stands still at a stop, then pulls away', () {
      final t = build(calmPlan());
      final atStop = targetAt(t, 20);

      // Standing: the whole dwell passes without the plan moving on.
      for (final s in [20.5, 21.0, 22.0, 22.9]) {
        expect(targetAt(t, s), closeTo(atStop, 0.5),
            reason: 'should still be standing at the stop at ${s}s');
      }
      // ...and then it goes again.
      expect(targetAt(t, 25), greaterThan(atStop + 2));
    });

    test('it brakes into the stop instead of arriving at full speed', () {
      final t = build(calmPlan());
      // Speed over the last four seconds of the approach must fall away, so the
      // marker stops AT the stop rather than sailing past it and reversing up
      // (the marker's own limiter only brakes once it sees the gap).
      final speeds = [16, 17, 18, 19]
          .map((s) => targetAt(t, s + 1) - targetAt(t, s.toDouble()))
          .toList();
      for (var i = 1; i < speeds.length; i++) {
        expect(speeds[i], lessThan(speeds[i - 1]),
            reason: 'approach speed should keep dropping: $speeds');
      }
      expect(speeds.last, lessThan(1.0), reason: 'should be nearly stopped');
    });

    test('the waypoints themselves are untouched — position and time', () {
      // The honesty invariant, and why total plan time cannot drift: the dwell
      // only reshapes the curve *between* waypoints. Each stop is still reached
      // at exactly the second the upstream said, at exactly its own position.
      final t = build(calmPlan());
      final path = _eastRoute();
      for (final p in calmPlan()) {
        final planned = path.project(ll.LatLng(p.lat, p.lon));
        expect(targetAt(t, p.etaSeconds.toDouble()), closeTo(planned, 1.0),
            reason: 'waypoint at ${p.etaSeconds}s must not move');
      }
    });

    test('never rushes: the plan stays within a plausible speed', () {
      // A dwell's seconds come out of the segment, so the cruise speeds up. That
      // must not turn into a bus doing 60+ km/h between two stops.
      final t = build(calmPlan());
      var peak = 0.0;
      for (var s = 0; s < 45; s++) {
        final v = targetAt(t, s + 1.0) - targetAt(t, s.toDouble());
        if (v > peak) peak = v;
      }
      expect(peak, lessThan(16.7), reason: 'peak ${peak.toStringAsFixed(1)} m/s');
    });

    test('a brisk segment keeps the even glide rather than fake a pause', () {
      // 237 m in 28 s from a standstill to a standstill needs an implausible
      // sprint. Better the old even glide than an invented one.
      final t = build(briskPlan());
      // Sample inside the 45 s staleness gate: past it the target collapses back
      // to the fix by design, which is a different behaviour entirely.
      final speeds = [
        for (var s = 30; s < 43; s++)
          targetAt(t, s + 1.0) - targetAt(t, s.toDouble())
      ];
      for (final v in speeds) {
        expect(v, greaterThan(4.0), reason: 'should never stand still: $speeds');
      }
    });

    test('does not brake into a stop the plan then leaves at full speed', () {
      // The regression this cost us: braking to a halt in front of a segment
      // that glides away stranded the marker ~12 m behind, which it made up with
      // a 52 km/h surge out of a stop whose plan said 32 — the exact catch-up
      // jerk this feature exists to remove.
      final t = build(briskPlan());
      var worstGap = 0.0;
      for (var f = 0; f <= 44 * 30; f++) {
        final now = _t0.add(Duration(milliseconds: f * 1000 ~/ 30));
        t.advance(now);
        // Measure around the stop (at 28 s) only. The first seconds are the
        // marker easing in from rest — it starts still and the plan doesn't, so
        // it legitimately trails ~12 m there. That's long-standing behaviour
        // (see 'eases in from rest' above), not this segment's doing.
        if (f < 20 * 30) continue;
        final gap = t.catchUpGap(now);
        if (gap > worstGap) worstGap = gap;
      }
      expect(worstGap, lessThan(3.0),
          reason: 'marker fell ${worstGap.toStringAsFixed(1)} m behind the plan');
    });

    test('the marker follows the dwell without ever jerking or reversing', () {
      final t = build(calmPlan());
      var prevDist = t.displayDistance;
      var prevV = 0.0;
      var stoodStill = false;
      for (var f = 0; f <= 45 * 30; f++) {
        final now = _t0.add(Duration(milliseconds: f * 1000 ~/ 30));
        t.advance(now);
        // Forward-only, always.
        expect(t.displayDistance, greaterThanOrEqualTo(prevDist - 1e-6));
        // Bounded acceleration ⇒ no jerk. (3.0 m/s² is the marker's chase limit;
        // allow a hair for floating point.)
        expect((t.displaySpeed - prevV).abs() * 30, lessThan(3.2),
            reason: 'velocity stepped at frame $f');
        final elapsed = f / 30;
        if (elapsed > 21 && elapsed < 23 && t.displaySpeed < 0.1) {
          stoodStill = true;
        }
        prevDist = t.displayDistance;
        prevV = t.displaySpeed;
      }
      expect(stoodStill, isTrue, reason: 'the marker never actually paused');
    });

    test('a fresh board (age ~0) is playing, not frozen', () {
      // Regression: isPlaying gated on `elapsed <= 0`, which is true both for a
      // stale board AND for a fresh one that just landed (age ~0). The fresh
      // case wrongly read as "not playing", so the ticker parked and the marker
      // sat mid-block the instant a new board arrived (owner screen: plan 8.0,
      // vel 0.0, movingNow 0, age 0s).
      final t = build(calmPlan());
      // now == asOf → age 0 → `_targetElapsed` 0, but the plan is live.
      expect(t.isPlaying(_t0), isTrue,
          reason: 'a just-landed board must keep the marker playing');
      expect(t.hasForwardMotion(_t0), isTrue);
      // A genuinely stale board (90 s) is still held.
      final stale = _t0.add(const Duration(seconds: 90));
      expect(t.isPlaying(stale), isFalse);
    });

    test('a dwell keeps the ticker alive but does not count as movement', () {
      // isPlaying vs hasForwardMotion. Parking the ticker on a dwell would leave
      // nothing running to end it — the 3 s pause would become a permanent
      // freeze (invisible on a busy map, fatal with a single followed vehicle).
      final t = build(calmPlan());
      final midDwell = _t0.add(const Duration(milliseconds: 21500));
      for (var f = 0; f <= 22 * 30; f++) {
        t.advance(_t0.add(Duration(milliseconds: f * 1000 ~/ 30)));
      }
      expect(t.hasForwardMotion(midDwell), isFalse,
          reason: 'standing at a stop is genuinely not moving');
      expect(t.isPlaying(midDwell), isTrue,
          reason: 'but the plan still has motion to come — keep rendering');

      // A stale board is the real "nothing left to render": both go quiet.
      final stale = _t0.add(const Duration(seconds: 90));
      expect(t.isPlaying(stale), isFalse);
      expect(t.hasForwardMotion(stale), isFalse);
    });
  });
}
