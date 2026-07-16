import 'dart:math' as math;

import 'package:latlong2/latlong.dart' as ll;

import '../domain/models/trajectory_point.dart';
import 'route_path.dart';

/// A time-driven player over a vehicle's forward timing plan (the backend
/// `trajectory`: where the vehicle will be and when, anchored at an as-of time),
/// projected onto the route's road geometry.
///
/// It turns "as-of time + planned (position, eta) waypoints" into a *displayed*
/// distance-along the route at any wall-clock instant. Three guarantees, taken
/// from the reference behaviour and the owner's brief:
///   * **Forward only.** The displayed distance is monotonic non-decreasing —
///     a fresher plan that recalculates ETAs shorter or longer never rewinds the
///     marker. When the plan says the vehicle is *behind* where the marker
///     already shows (we overran), the marker holds and waits instead of
///     reversing.
///   * **No teleport.** When a new plan puts the vehicle further ahead, the
///     marker converges smoothly (exponential approach) rather than snapping.
///   * **Never past the plan.** The displayed distance is clamped to the plan's
///     final waypoint, so the marker never runs beyond the last known point.
///
/// Pure and widget-free so it can be unit-tested without a map. All time comes
/// in as arguments, so tests drive it with a virtual clock.
class TimedTrajectory {
  TimedTrajectory._(this._path, this._waypoints, this._asOf, this._dispDist,
      this._lastAdvance);

  RoutePath _path;
  List<_Waypoint> _waypoints; // distance ↑, eta ↑; the first eta is ~0
  DateTime _asOf;
  double _dispDist;
  double _dispVel = 0; // displayed speed along the path (m/s) — a state variable
  DateTime _lastAdvance;

  // Catch-up dynamics. The marker chases the plan's *predicted-now* spot, which
  // moves forward at the plan's own speed. To close the residual gap without the
  // periodic lurch an exponential approach produced (its velocity is maximal at
  // the instant each poll reveals the gap → a velocity step = a visible jerk),
  // the closing motion is acceleration-limited and velocity-continuous:
  //
  //   * The marker rides the plan speed as a *feed-forward* term, so once caught
  //     up it tracks the ramp with ~zero lag and no fresh gap re-appears each
  //     poll (which is what re-triggered the jerk).
  //   * On top of that it closes the position gap at a speed that is capped
  //     ([_maxCatchUpSpeed], an even cruise) and eased down to zero as it arrives
  //     (a sqrt profile → decelerate at [_maxCatchUpAccel], no jolt on arrival).
  //   * Velocity itself may change by at most [_maxCatchUpAccel]·dt per step, so
  //     it eases *in* when a gap appears and can never step discontinuously — the
  //     jerk is gone by construction (bounded acceleration ⇒ continuous velocity).
  //
  // Tuned for a transit marker: ~3 m/s² feels smooth (not a snap, not a crawl),
  // and an 18 m/s cap recovers even a large stale-recovery gap in a few seconds
  // while never cruising implausibly fast.
  static const double _maxCatchUpAccel = 3.0; // m/s²
  static const double _maxCatchUpSpeed = 18.0; // m/s, closing speed cap

  // A plan step shorter than this (metres) isn't worth treating as motion.
  static const double _epsilonMeters = 0.5;

  // Continuous prediction while the board is fresh, hard-stopped once it isn't.
  //
  // The plan is a forward (position, eta) table anchored at `as_of`; the marker
  // chases `plan[now - as_of]` — the vehicle's *predicted current* spot — so on
  // healthy 30s data it moves continuously across the whole poll interval (the
  // reference apps do exactly this) instead of leading a short bridge and then
  // sitting until the next batch, which read as the whole city freezing and
  // reviving in lockstep.
  //
  // The upstream board's `as_of` can go badly stale (upstream 503s under load →
  // SWR serves a frozen board, so `now - as_of` grows unbounded). Predicting
  // that unbounded gap from a frozen anchor is exactly what made markers "fly
  // while the vehicle is parked". The defence is NOT a short prediction window —
  // it's the [_stalenessSeconds] gate: while the fix is fresh we predict the
  // full elapsed time; once it's older than the gate (the board isn't
  // refreshing) we stop predicting and hold at the fix. The gate (45s) sits
  // above the 30s poll cadence, so healthy data never touches it (continuous
  // motion) while a frozen board is caught within one gate-width (hold, never
  // fly). [_maxAheadMeters] is the matching distance belt — the furthest the
  // marker may lead within that window, so an implausibly fast plan can't
  // outrun the gate.
  static const double _stalenessSeconds = 45;
  static const double _maxAheadMeters = 900;

  // The elapsed time used to place the *target* along the plan: the full time
  // since the fix while it's fresh (continuous prediction), and zero (sit at the
  // fix) once it's stale. This — not the raw `now - as_of` used unconditionally —
  // is what the marker chases, so a stale/frozen board can't fly it forward: the
  // moment the fix ages past the gate the target collapses back to the fix and
  // the forward-only [advance] simply holds (never lurches or rewinds).
  double _targetElapsed(DateTime now) => _gatedElapsed(_asOf, now);

  static double _gatedElapsed(DateTime asOf, DateTime now) {
    final age = _elapsedSeconds(asOf, now);
    if (age > _stalenessSeconds) return 0; // stale board: don't predict, hold
    return age; // fresh board: predict the full elapsed time (continuous)
  }

  /// Builds a player, or null when the plan/path can't form a usable monotone
  /// distance-vs-time table (needs a usable path and ≥2 strictly-forward points).
  static TimedTrajectory? build({
    required RoutePath path,
    required List<TrajectoryPoint> plan,
    required DateTime asOf,
    required DateTime now,
  }) {
    final wps = _project(path, plan);
    if (wps == null) return null;
    // Appear at the *predicted current* spot — the fix (plan point 0) projected
    // forward by the gated elapsed time — so a vehicle entering the viewport
    // mid-interval shows up where it actually is, not at a stale GPS point it
    // then races to catch up to (a visible forward lurch on every appearance,
    // worse the wider the prediction window). The gate keeps this honest: a
    // stale board (age past the gate) projects zero, so it still appears AT the
    // fix and holds — never flying in from a frozen anchor. Bounded to the
    // distance horizon as a belt against an implausibly fast plan.
    final gated = _gatedElapsed(asOf, now);
    var dispDist = _distAtElapsed(wps, gated);
    final horizon = wps.first.dist + _maxAheadMeters;
    if (dispDist > horizon) dispDist = horizon;
    return TimedTrajectory._(path, wps, asOf, dispDist, now);
  }

  /// Adopts a fresher plan without ever moving the marker backward: the current
  /// displayed distance is preserved (only clamped down if the new plan is
  /// shorter than where we already are). Returns false — leaving the old plan
  /// untouched — when the new plan can't be projected.
  bool updatePlan({
    required RoutePath path,
    required List<TrajectoryPoint> plan,
    required DateTime asOf,
    required DateTime now,
  }) {
    final wps = _project(path, plan);
    if (wps == null) return false;
    // When the *geometry itself* changes — the plan-point fallback upgrading to
    // the road shape, or a fresh fallback path — a raw distance-along on the old
    // path means nothing on the new one. Capture the current geographic position
    // first and re-anchor onto the new geometry at the same spot, so the upgrade
    // is seamless instead of jumping. Same-path updates keep the shown distance
    // (monotonic, never rewind).
    final pathChanged = !identical(path, _path);
    final ll.LatLng? geoBefore = pathChanged ? position : null;
    _path = path;
    _waypoints = wps;
    _asOf = asOf;
    _lastAdvance = now;
    if (geoBefore != null) {
      _dispDist = path.project(geoBefore);
    }
    // Never rewind: keep the shown distance, only clamp into the new plan's end.
    final end = wps.last.dist;
    if (_dispDist > end) _dispDist = end;
    return true;
  }

  /// Advances the displayed distance toward where the plan says the vehicle is
  /// *now*. Forward-only: holds (never reverses) when the plan is behind the
  /// marker, converges smoothly when it's ahead, clamps at the plan's end.
  ///
  /// The motion is acceleration-limited and velocity-continuous (see the class
  /// notes): it rides the plan speed as a feed-forward term and closes any
  /// residual gap with an eased, capped closing speed, so it never lurches.
  void advance(DateTime now) {
    final horizon = _horizonDist;
    final target = _gatedTarget(now);
    final dt = now.difference(_lastAdvance).inMicroseconds / 1e6;
    _lastAdvance = now;
    if (dt <= 0) return;

    // Feed-forward: how fast the *target itself* is moving right now (0 when the
    // board is stale — the target is pinned to the fix — or when it has reached
    // the horizon/plan end). Measured on the same gated model so all those
    // hold-cases fall out automatically.
    final planVel = _targetSpeed(now);

    // Target speed for this frame: ride the plan speed, plus a closing term that
    // erases the position gap — eased so arrival has no jolt (cruise at the cap
    // when far, sqrt ramp-down when near → decelerate at _maxCatchUpAccel).
    final gap = target - _dispDist;
    double desiredVel;
    if (gap <= _epsilonMeters) {
      desiredVel = 0; // caught up / overran: aim to hold; the ramp pulls us on
    } else {
      final closing =
          math.min(_maxCatchUpSpeed, math.sqrt(2 * _maxCatchUpAccel * gap));
      // Never *command* a speed that would fly past the target in one step; this
      // single cap also lands coarse (test-sized) steps exactly on the target.
      desiredVel = math.min(planVel + closing, gap / dt);
    }

    // Acceleration limit — the velocity may change by at most _maxCatchUpAccel·dt
    // per step. This is the ease-in when a gap appears and guarantees a
    // continuous velocity (no step ⇒ no jerk). One update only, so |Δv| is truly
    // bounded. Never negative (forward-only).
    final maxDv = _maxCatchUpAccel * dt;
    _dispVel += (desiredVel - _dispVel).clamp(-maxDv, maxDv);
    if (_dispVel < 0) _dispVel = 0;

    var next = _dispDist + _dispVel * dt;
    if (next >= horizon) {
      next = horizon;
      _dispVel = 0;
    }
    if (next < _dispDist) {
      next = _dispDist; // forward-only: hold when the plan is behind us
      _dispVel = 0;
    }
    _dispDist = next;
  }

  // The gated, horizon-clamped target distance the marker chases at [now].
  double _gatedTarget(DateTime now) {
    final t = _distAtElapsed(_waypoints, _targetElapsed(now));
    final horizon = _horizonDist;
    return t > horizon ? horizon : t;
  }

  // The target's own forward speed (m/s) at [now], via a short finite difference
  // on the same gated model — automatically 0 when stale or clamped (nothing to
  // feed forward), non-negative otherwise.
  double _targetSpeed(DateTime now) {
    const eps = 0.25; // s
    final v = (_gatedTarget(now.add(const Duration(milliseconds: 250))) -
            _gatedTarget(now)) /
        eps;
    return v > 0 ? v : 0;
  }

  double get displayDistance => _dispDist;
  double get endDistance => _waypoints.last.dist;

  /// Displayed speed along the path (m/s) — a diagnostics read-out for the
  /// catch-up instrumentation (staging overlay).
  double get displaySpeed => _dispVel;

  /// How far behind the plan's predicted-now spot the marker currently is (m,
  /// never negative) — the live "catch-up distance" for the staging overlay.
  double catchUpGap(DateTime now) {
    final gap = _gatedTarget(now) - _dispDist;
    return gap > 0 ? gap : 0;
  }

  // The furthest distance-along the marker may predict to right now: the plan's
  // end, but no more than [_maxAheadMeters] past the last fix (waypoint 0). Keeps
  // extrapolation restrained when fresh fixes stop coming.
  double get _horizonDist {
    final byDistance = _waypoints.first.dist + _maxAheadMeters;
    final end = endDistance;
    return byDistance < end ? byDistance : end;
  }

  ll.LatLng get position => _path.pointAt(_dispDist);
  // Smoothed (look-ahead) bearing: turns continuously through a curve so the
  // direction arrow rotates smoothly instead of snapping vertex-to-vertex (which
  // reads as a zigzag on a road-accurate, ~15 m-spaced GTFS shape).
  double get heading => _path.headingAtSmoothed(_dispDist, forward: true);

  /// Whether the marker still has forward motion to render at [now]. False once
  /// it has reached the plan's end or wall-clock has run past the plan's horizon
  /// (no fresh data) — the caller then parks the ticker (idle = zero frames).
  bool hasForwardMotion(DateTime now) {
    if (_dispDist >= _horizonDist - _epsilonMeters) return false;
    // Motion only while the (staleness-gated) target is still ahead of the
    // display. While the fix is fresh the target advances with wall-clock, so
    // this stays true across the whole poll interval (continuous motion). Once
    // the fix goes stale the target collapses to the fix, the marker settles,
    // and the ticker parks (idle = zero frames); the grace fade then removes a
    // vehicle that also dropped from the feed.
    final target = _distAtElapsed(_waypoints, _targetElapsed(now));
    return target > _dispDist + _epsilonMeters;
  }

  // Projects each plan point onto [path], keeping only strictly-forward,
  // strictly-later waypoints (a projection can fold a point back on a looped
  // route; a recomputed ETA can tie). Needs ≥2 to be usable.
  static List<_Waypoint>? _project(RoutePath path, List<TrajectoryPoint> plan) {
    if (!path.isUsable || plan.length < 2) return null;
    final wps = <_Waypoint>[];
    double? near;
    for (final p in plan) {
      final d = path.project(ll.LatLng(p.lat, p.lon), near: near);
      near = d;
      final eta = p.etaSeconds.toDouble();
      if (wps.isEmpty) {
        wps.add(_Waypoint(d, eta));
        continue;
      }
      final last = wps.last;
      if (d > last.dist + _epsilonMeters && eta > last.etaSeconds) {
        wps.add(_Waypoint(d, eta));
      }
    }
    return wps.length >= 2 ? wps : null;
  }

  static double _elapsedSeconds(DateTime asOf, DateTime now) {
    final s = now.difference(asOf).inMicroseconds / 1e6;
    return s < 0 ? 0 : s;
  }

  // Piecewise-linear distance for an elapsed time, clamped to the plan's ends.
  static double _distAtElapsed(List<_Waypoint> wps, double elapsed) {
    if (elapsed <= wps.first.etaSeconds) return wps.first.dist;
    if (elapsed >= wps.last.etaSeconds) return wps.last.dist;
    // Linear scan is fine: plans are short (≤ ~80 points).
    for (var i = 0; i < wps.length - 1; i++) {
      final a = wps[i], b = wps[i + 1];
      if (elapsed <= b.etaSeconds) {
        final span = b.etaSeconds - a.etaSeconds;
        final f = span == 0 ? 0.0 : (elapsed - a.etaSeconds) / span;
        return a.dist + (b.dist - a.dist) * f;
      }
    }
    return wps.last.dist;
  }
}

class _Waypoint {
  const _Waypoint(this.dist, this.etaSeconds);
  final double dist;
  final double etaSeconds;
}
