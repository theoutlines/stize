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
  DateTime _lastAdvance;

  // Exponential-approach time constant used when the plan is ahead of the
  // marker: the marker closes ~63% of the gap every this-many seconds. Small
  // enough to feel responsive, large enough that an ETA-shorter recalculation
  // eases in over ~1-2s instead of jumping.
  static const double _convergeTau = 2.5;

  // A plan step shorter than this (metres) isn't worth treating as motion.
  static const double _epsilonMeters = 0.5;

  // Restrained extrapolation — how far the marker is allowed to *predict* past
  // the last real fix before it holds and waits for fresh data, so it leads
  // reality without "running away" / the map living its own life. Normally moot
  // (a fresh fix lands every ~30s, resetting both), these only bite when data
  // stops (vehicle left the fan-out, a feed gap): the marker coasts at most this
  // far ahead in time OR distance, then parks (and the grace fade takes over).
  static const double _maxLookaheadSeconds = 60;
  static const double _maxAheadMeters = 500;

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
    final start = _distAtElapsed(wps, _elapsedSeconds(asOf, now));
    return TimedTrajectory._(path, wps, asOf, start, now);
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
  void advance(DateTime now) {
    final elapsed = _elapsedSeconds(_asOf, now);
    final capped = elapsed < _maxLookaheadSeconds ? elapsed : _maxLookaheadSeconds;
    final horizon = _horizonDist;
    var target = _distAtElapsed(_waypoints, capped);
    if (target > horizon) target = horizon;
    final dt = now.difference(_lastAdvance).inMicroseconds / 1e6;
    _lastAdvance = now;
    if (dt > 0 && target > _dispDist) {
      final gap = target - _dispDist;
      _dispDist += gap * (1 - math.exp(-dt / _convergeTau));
      if (_dispDist > target) _dispDist = target;
    }
    if (_dispDist > horizon) _dispDist = horizon;
  }

  double get displayDistance => _dispDist;
  double get endDistance => _waypoints.last.dist;

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
    // Only predict up to the look-ahead window past the plan's as-of time; once
    // fresh data has stopped for longer than that, park (the grace fade removes
    // it) instead of coasting on indefinitely.
    return _elapsedSeconds(_asOf, now) < _maxLookaheadSeconds;
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
