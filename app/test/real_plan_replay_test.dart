import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:stigla/core/route_path.dart';
import 'package:stigla/core/timed_trajectory.dart';
import 'package:stigla/core/vehicle_track_animator.dart';
import 'package:stigla/domain/models/trajectory_point.dart';
import 'package:stigla/domain/models/vehicle_type.dart';

/// Replays a **real** plan on its **real** GTFS shape at 60 fps, refreshing the
/// plan every 30 s exactly as the client does.
///
/// This file exists because synthetic plans hid a bug that shipped. A made-up
/// plan let us pick speeds and segment lengths that happened to look fine; the
/// real line 5 is a slow tram (a ~1.3 m/s segment between two stations 176 m
/// apart), and at that speed the catch-up loop's limit cycle bottomed out at a
/// standstill — the marker appeared to stop mid-block, at no stop at all, and
/// sawed forever. None of it was visible until a real plan was driven at frame
/// resolution. Keep the replay real.
void main() {
  final raw =
      jsonDecode(File('test/fixtures/real_plan_line5.json').readAsStringSync())
          as Map<String, dynamic>;
  final path = RoutePath.fromLatLon((raw['polyline'] as List)
      .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
      .toList())!;
  final plan = (raw['trajectory'] as List)
      .map((e) => TrajectoryPoint.fromJson(e as Map<String, dynamic>))
      .toList();
  final t0 = DateTime(2026, 1, 1, 12);

  /// Drives the player for [seconds], refreshing the plan every 30 s (a board
  /// lands ~2 s old — measured). Calls [sample] each frame once past [settleAt].
  void replay({
    required double seconds,
    required double settleAt,
    required void Function(
            double t, double markerV, double targetV, double gap, bool moving)
        sample,
    void Function(double t, TimedTrajectory tt, DateTime now)? onFrame,
  }) {
    final t = TimedTrajectory.build(path: path, plan: plan, asOf: t0, now: t0)!;
    var lastPlanAt = t0;
    var prevTarget = t.targetDistanceAt(t0);
    for (var f = 0; f <= seconds * 60; f++) {
      final now = t0.add(Duration(milliseconds: f * 1000 ~/ 60));
      if (now.difference(lastPlanAt).inSeconds >= 30) {
        lastPlanAt = now;
        final asOf = now.subtract(const Duration(seconds: 2));
        final elapsed = asOf.difference(t0).inMilliseconds / 1000.0;
        final ahead = plan.where((p) => p.etaSeconds > elapsed).toList();
        if (ahead.length < 2) break;
        final at = path.pointAt(t.targetDistanceAt(asOf));
        t.updatePlan(
          path: path,
          plan: [
            TrajectoryPoint(at.latitude, at.longitude, 0),
            for (final p in ahead)
              TrajectoryPoint(p.lat, p.lon, (p.etaSeconds - elapsed).round()),
          ],
          asOf: asOf,
          now: now,
        );
      }
      t.advance(now);
      final target = t.targetDistanceAt(now);
      final targetV = (target - prevTarget) * 60;
      prevTarget = target;
      final secs = f / 60;
      if (secs >= settleAt) {
        sample(secs, t.displaySpeed, targetV, t.catchUpGap(now),
            t.hasForwardMotion(now));
        onFrame?.call(secs, t, now);
      }
    }
  }

  test('the marker holds a steady speed where the plan holds one', () {
    // The regression: within _epsilonMeters of the target the loop used to
    // command a dead stop, throwing away the plan's speed. Tracking perfectly
    // still leaves gap == planVel·dt (~22 mm at 60 fps), always inside that
    // epsilon — so it fired every frame and the marker sawed between ~0 and ~2×
    // the plan speed forever, gap pinned at 0.5 m.
    //
    // Window: a flat-cruise stretch with no plan refresh in it, so any swing
    // here is the loop arguing with itself rather than reacting to new data.
    var minV = double.infinity, maxV = -double.infinity, maxGap = 0.0;
    replay(
      seconds: 44,
      settleAt: 32,
      sample: (t, markerV, targetV, gap, moving) {
        if (markerV < minV) minV = markerV;
        if (markerV > maxV) maxV = markerV;
        if (gap > maxGap) maxGap = gap;
      },
    );
    expect(maxV - minV, lessThan(0.15),
        reason: 'marker speed swung ${(maxV - minV).toStringAsFixed(2)} m/s '
            '(${minV.toStringAsFixed(2)}..${maxV.toStringAsFixed(2)}) while the '
            'plan held a flat cruise — the catch-up loop is oscillating');
    // The gap must settle at ~planVel·dt, not at the old epsilon boundary.
    expect(maxGap, lessThan(0.2),
        reason: 'gap parked at ${maxGap.toStringAsFixed(2)} m');
  });

  test('the marker never stands still while the plan is moving', () {
    // The other face of the same bug: on a slow segment each trough of the limit
    // cycle reached zero, so the marker looked like it was pausing mid-block —
    // at no stop at all. A standstill is only legitimate while the plan itself
    // stands still (a stop dwell).
    final fakeStops = <String>[];
    replay(
      seconds: 44,
      settleAt: 10,
      sample: (t, markerV, targetV, gap, moving) {
        if (markerV < 0.05 && targetV > 0.5) {
          fakeStops.add('t=${t.toStringAsFixed(1)}s targetV='
              '${targetV.toStringAsFixed(2)}');
        }
      },
    );
    expect(fakeStops, isEmpty,
        reason: 'marker stood still while the plan was moving: '
            '${fakeStops.take(5).join(", ")}');
  });

  test('a moving vehicle reports as moving — the spiderfy gate depends on it', () {
    // The contract (c5f4547): vehicles in MOTION are never displaced; two that
    // converge pass over each other, fading, and only *stationary* coincident
    // ones fan apart. The gate is `moving`, and it comes from here.
    //
    // It has been lying. hasForwardMotion used to compare the marker's
    // instantaneous distance-from-target against 0.5 m, but a marker tracking
    // perfectly sits planVel·dt (~22 mm at 60 fps) behind — so a moving vehicle
    // read as stationary on every frame, and moving markers shoved each other
    // aside on production. Measured before the fix: 0 of 2101 frames reported
    // motion while the plan was actively moving the vehicle.
    var movingFrames = 0, total = 0;
    replay(
      seconds: 40,
      settleAt: 5,
      sample: (t, markerV, targetV, gap, moving) {
        if (targetV < 0.5) return; // only judge frames where the plan IS moving
        total++;
        if (moving) movingFrames++;
      },
    );
    expect(total, greaterThan(600), reason: 'need a decent sample of moving frames');
    expect(movingFrames, total,
        reason: 'a moving vehicle reported as stationary on '
            '${total - movingFrames} of $total frames — it will be spiderfied '
            'apart from its neighbours');
  });

  test('the animator agrees: a live timed vehicle is moving, a stale one is not', () {
    // The seam the map actually reads: `moving: _vehAnimator.hasMotion(key)`.
    final t0 = DateTime(2026, 1, 1, 12);
    var clock = t0;
    final animator = VehicleTrackAnimator(clock: () => clock);
    animator.syncSamples([
      VehicleSample(
        key: 'P80383',
        position: ll.LatLng(plan.first.lat, plan.first.lon),
        line: '5',
        type: VehicleType.tram,
        path: path,
        trajectory: plan,
        asOf: t0,
      ),
    ], 0, now: t0);

    clock = t0.add(const Duration(seconds: 12));
    animator.advanceTimed(clock);
    expect(animator.hasMotion('P80383'), isTrue,
        reason: 'a live, moving vehicle must not be spiderfied');

    // Board goes stale (past the 45 s gate): now it genuinely is parked.
    clock = t0.add(const Duration(seconds: 200));
    animator.advanceTimed(clock);
    expect(animator.hasMotion('P80383'), isFalse,
        reason: 'a frozen vehicle should fan out normally');
  });

  test('a dwell still happens, and only where the plan itself stands still', () {
    var dwellFrames = 0;
    var mismatched = 0;
    replay(
      seconds: 44,
      settleAt: 10,
      sample: (t, markerV, targetV, gap, moving) {
        if (targetV < 0.01) {
          dwellFrames++;
          if (markerV > 0.15) mismatched++;
        }
      },
    );
    expect(dwellFrames, greaterThan(60),
        reason: 'the real plan should still pause at its first station');
    expect(mismatched, lessThan(dwellFrames ~/ 4),
        reason: 'the marker kept rolling through the plan\'s standstill');
  });

  test('a vehicle pausing at a stop is not fanned apart either', () {
    // The owner's call, and the right one: a dwell is stillness that resolves
    // itself in three seconds. Fanning a bus out on arrival and collapsing it
    // again as it pulls away would be a shove every stop — the very churn the
    // pass-through contract exists to prevent. Only a genuinely parked vehicle
    // (stale board, plan exhausted) fans.
    //
    // So `moving` for spiderfy reads isPlaying, not hasForwardMotion: the dwell
    // is *not* motion (the stuck heuristic must still see a standstill), but it
    // *is* the plan playing.
    var dwellFrames = 0, fannable = 0;
    replay(
      seconds: 44,
      settleAt: 10,
      sample: (t, markerV, targetV, gap, moving) {},
      onFrame: (t, tt, now) {
        if (tt.planSpeed(now) < 0.01 && !tt.isStale(now)) {
          dwellFrames++;
          if (!tt.isPlaying(now)) fannable++;
        }
      },
    );
    expect(dwellFrames, greaterThan(60), reason: 'no dwell in the window');
    expect(fannable, 0,
        reason: 'a vehicle standing at a stop was fannable on $fannable of '
            '$dwellFrames dwell frames — it would be shoved aside and snap back');
  });

  test('the marker only ever stands still at a stop', () {
    // A standstill says "this vehicle is at a stop". Mid-block that is a lie —
    // and a costlier one now that dwells are rendered, because a standstill is
    // how the map says "stop".
    //
    // The marker is held back all the time: the upstream's ETAs are optimistic,
    // so a 30 s prediction runs ahead of the real vehicle, and the next fix lands
    // *behind* the marker. Forward-only forbids rewinding, so it waits. Freezing
    // is the wrong way to show waiting. Replayed here with a vehicle running 20%
    // slower than its plan and re-anchored on real fixes every 30 s — the case a
    // single self-consistent plan can never surface, which is why this went out.
    final wpDist = [for (final p in plan) path.project(ll.LatLng(p.lat, p.lon))];
    final stations = wpDist.sublist(1); // waypoint 0 is the GPS
    double offNearestStation(double d) => stations
        .map((s) => (d - s).abs())
        .reduce((a, b) => a < b ? a : b);

    // Ground truth: the planned curve on a stretched clock.
    double truthAt(double secs) {
      final e = secs * 0.8;
      for (var i = 0; i < plan.length - 1; i++) {
        if (e <= plan[i + 1].etaSeconds) {
          final a = plan[i].etaSeconds.toDouble();
          final b = plan[i + 1].etaSeconds.toDouble();
          return wpDist[i] + (wpDist[i + 1] - wpDist[i]) * (e - a) / (b - a);
        }
      }
      return wpDist.last;
    }

    final t = TimedTrajectory.build(path: path, plan: plan, asOf: t0, now: t0)!;
    var lastPlanAt = t0;
    var standStart = -1.0, standAt = 0.0;
    final offPinStands = <String>[];
    for (var f = 0; f <= 150 * 60; f++) {
      final now = t0.add(Duration(milliseconds: f * 1000 ~/ 60));
      final secs = f / 60;
      if (now.difference(lastPlanAt).inSeconds >= 30) {
        lastPlanAt = now;
        final asOf = now.subtract(const Duration(seconds: 2));
        final truth = truthAt(asOf.difference(t0).inMilliseconds / 1000.0);
        // The upstream re-anchors on the real fix but keeps its optimistic pace.
        final ahead = <TrajectoryPoint>[];
        var acc = 0.0;
        for (var i = 0; i < plan.length - 1; i++) {
          if (wpDist[i + 1] <= truth) continue;
          acc += (plan[i + 1].etaSeconds - plan[i].etaSeconds).toDouble();
          ahead.add(TrajectoryPoint(plan[i + 1].lat, plan[i + 1].lon, acc.round()));
        }
        if (ahead.length < 2) break;
        final gps = path.pointAt(truth);
        t.updatePlan(
          path: path,
          plan: [TrajectoryPoint(gps.latitude, gps.longitude, 0), ...ahead],
          asOf: asOf,
          now: now,
        );
      }
      t.advance(now);
      if (t.displaySpeed < 0.05) {
        if (standStart < 0) {
          standStart = secs;
          standAt = t.displayDistance;
        }
      } else if (standStart >= 0) {
        final off = offNearestStation(standAt);
        if (secs - standStart >= 0.4 && off > 20.0) {
          offPinStands.add('${(secs - standStart).toStringAsFixed(1)}s at '
              '${off.toStringAsFixed(0)}m out (t=${standStart.toStringAsFixed(0)}s)');
        }
        standStart = -1;
      }
    }
    expect(offPinStands, isEmpty,
        reason: 'the marker stood still away from any stop: '
            '${offPinStands.join("; ")}');
  });
}
