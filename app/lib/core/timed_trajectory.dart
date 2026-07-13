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
    _path = path;
    _waypoints = wps;
    _asOf = asOf;
    _lastAdvance = now;
    // Never rewind: keep the shown distance, only clamp into the new plan's end.
    final end = wps.last.dist;
    if (_dispDist > end) _dispDist = end;
    return true;
  }

  /// Advances the displayed distance toward where the plan says the vehicle is
  /// *now*. Forward-only: holds (never reverses) when the plan is behind the
  /// marker, converges smoothly when it's ahead, clamps at the plan's end.
  void advance(DateTime now) {
    final target = _distAtElapsed(_waypoints, _elapsedSeconds(_asOf, now));
    final dt = now.difference(_lastAdvance).inMicroseconds / 1e6;
    _lastAdvance = now;
    if (dt > 0 && target > _dispDist) {
      final gap = target - _dispDist;
      _dispDist += gap * (1 - math.exp(-dt / _convergeTau));
      if (_dispDist > target) _dispDist = target;
    }
    final end = endDistance;
    if (_dispDist > end) _dispDist = end;
  }

  double get displayDistance => _dispDist;
  double get endDistance => _waypoints.last.dist;
  DateTime get endTime =>
      _asOf.add(Duration(milliseconds: (_waypoints.last.etaSeconds * 1000).round()));

  ll.LatLng get position => _path.pointAt(_dispDist);
  // Smoothed (look-ahead) bearing: turns continuously through a curve so the
  // direction arrow rotates smoothly instead of snapping vertex-to-vertex (which
  // reads as a zigzag on a road-accurate, ~15 m-spaced GTFS shape).
  double get heading => _path.headingAtSmoothed(_dispDist, forward: true);

  /// Whether the marker still has forward motion to render at [now]. False once
  /// it has reached the plan's end or wall-clock has run past the plan's horizon
  /// (no fresh data) — the caller then parks the ticker (idle = zero frames).
  bool hasForwardMotion(DateTime now) {
    if (_dispDist >= endDistance - _epsilonMeters) return false;
    return now.isBefore(endTime);
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
