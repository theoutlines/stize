import 'dart:math' as math;

import 'package:latlong2/latlong.dart' as ll;

/// A route polyline (road-accurate GTFS geometry) with helpers to project a
/// point onto it and to sample a position/heading by distance-along.
///
/// This is what lets a live vehicle glide *along its route* between updates
/// instead of teleporting in a straight line through buildings (X5): we project
/// each real GPS fix onto the path to get a distance-along, then move the marker
/// smoothly between successive distances, staying on the road geometry the whole
/// way. Pure and Flutter-free so it can be unit-tested.
class RoutePath {
  RoutePath(this.points) : _cum = _cumulative(points);

  final List<ll.LatLng> points;
  final List<double> _cum; // cumulative metres at each vertex

  static const _d = ll.Distance();
  static const _metresPerDegree = 111320.0;

  double get length => _cum.isEmpty ? 0 : _cum.last;
  bool get isUsable => points.length >= 2;

  // Windowed-projection tuning (F1). A vehicle can only travel so far along its
  // route between two ~30s fixes, so when we know roughly where it was last
  // ([near]) we prefer a match within this window of that distance — this keeps
  // a fix on the return leg of an out-and-back (or a loop) from snapping onto
  // the geometrically-close *outbound* leg a few metres away.
  static const _projectWindow = 800.0; // metres either side of [near]
  // Only fall back to the global-nearest segment (ignoring [near]) when the
  // windowed match is this much worse perpendicular-distance — i.e. the vehicle
  // genuinely jumped (route re-match / long feed gap), not just noisy GPS.
  static const _localTolerance = 60.0; // metres

  /// Builds a path from a `[[lat, lon], ...]` polyline, or null if too short.
  static RoutePath? fromLatLon(List<List<double>>? poly) {
    if (poly == null || poly.length < 2) return null;
    return RoutePath([for (final p in poly) ll.LatLng(p[0], p[1])]);
  }

  static List<double> _cumulative(List<ll.LatLng> pts) {
    final cum = <double>[];
    var acc = 0.0;
    for (var i = 0; i < pts.length; i++) {
      if (i > 0) acc += _d(pts[i - 1], pts[i]);
      cum.add(acc);
    }
    return cum;
  }

  /// Distance-along the path (metres) of the closest point to [p].
  ///
  /// [near] disambiguates routes that fold back on themselves (out-and-back
  /// legs, loops): when supplied, a segment within [_projectWindow] of that
  /// distance-along is preferred over the raw global-nearest, so a fix on one
  /// leg doesn't snap onto a parallel leg a few metres away (F1). The global
  /// nearest is still used when the local match is markedly worse — the mark of
  /// a genuine jump (route re-match, long feed gap) rather than GPS noise.
  double project(ll.LatLng p, {double? near}) {
    var globalAlong = 0.0;
    var globalDist = double.infinity;
    var localAlong = 0.0;
    var localDist = double.infinity;
    for (var i = 0; i < points.length - 1; i++) {
      final seg = _projectOnSegment(p, points[i], points[i + 1]);
      final along = _cum[i] + (_cum[i + 1] - _cum[i]) * seg.t;
      if (seg.dist < globalDist) {
        globalDist = seg.dist;
        globalAlong = along;
      }
      if (near != null &&
          (along - near).abs() <= _projectWindow &&
          seg.dist < localDist) {
        localDist = seg.dist;
        localAlong = along;
      }
    }
    if (near != null &&
        localDist.isFinite &&
        localDist <= globalDist + _localTolerance) {
      return localAlong;
    }
    return globalAlong;
  }

  /// The position at [dist] metres along the path (clamped to its ends).
  /// Called every animation frame per vehicle, so the segment lookup is a
  /// binary search over the cumulative distances (O(log n)).
  ll.LatLng pointAt(double dist) {
    if (points.isEmpty) return const ll.LatLng(0, 0);
    if (points.length == 1) return points.first;
    final d = dist.clamp(0.0, length);
    final i = _segmentFor(d);
    final segLen = _cum[i + 1] - _cum[i];
    final t = segLen == 0 ? 0.0 : (d - _cum[i]) / segLen;
    return ll.LatLng(
      points[i].latitude + (points[i + 1].latitude - points[i].latitude) * t,
      points[i].longitude +
          (points[i + 1].longitude - points[i].longitude) * t,
    );
  }

  /// Compass bearing (0 = north, clockwise) of the segment containing [dist].
  /// [forward] false reverses it — for a vehicle travelling the path backward.
  double headingAt(double dist, {bool forward = true}) {
    if (points.length < 2) return 0;
    final i = _segmentFor(dist.clamp(0.0, length));
    final a = forward ? points[i] : points[i + 1];
    final b = forward ? points[i + 1] : points[i];
    return _bearing(a, b);
  }

  /// A *smoothed* travel bearing at [dist]: the bearing of the chord from the
  /// current point to a point [lookahead] metres further along (or, near the
  /// end, from a point [lookahead] behind up to the current point).
  ///
  /// The per-segment [headingAt] steps discretely at every vertex — on a
  /// road-accurate GTFS shape that's a new bearing every ~15 m, jumping 15–25°
  /// at a bend. A direction arrow driven by that snaps vertex-to-vertex, which
  /// reads as a zigzag on curves. Averaging over a span longer than one vertex
  /// spacing makes the heading turn *continuously* through a curve, so the arrow
  /// rotates smoothly. Both chord endpoints slide continuously with [dist], so
  /// the result has no discontinuities (only tiny kinks as an endpoint crosses a
  /// vertex, negligible over a 30 m span).
  double headingAtSmoothed(double dist, {double lookahead = 30, bool forward = true}) {
    if (points.length < 2) return 0;
    final d = dist.clamp(0.0, length);
    final ahead = math.min(d + lookahead, length);
    final behind = math.max(d - lookahead, 0.0);
    final ll.LatLng a, b;
    if (ahead - d > 1) {
      a = pointAt(d);
      b = pointAt(ahead);
    } else if (d - behind > 1) {
      // Within [lookahead] of the end: use the trailing chord instead.
      a = pointAt(behind);
      b = pointAt(d);
    } else {
      // Degenerate (path shorter than the window): fall back to the segment.
      return headingAt(dist, forward: forward);
    }
    final bearing = _bearing(a, b);
    return forward ? bearing : (bearing + 180) % 360;
  }

  // Index i such that _cum[i] <= d <= _cum[i+1], via binary search.
  int _segmentFor(double d) {
    var lo = 0;
    var hi = points.length - 1; // last valid segment start is length-2
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_cum[mid + 1] < d) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo.clamp(0, points.length - 2);
  }

  // Projects p onto segment a→b using a local equirectangular approximation
  // (accurate at city scale). Returns the clamped position t in [0,1] and the
  // perpendicular distance in metres.
  static ({double t, double dist}) _projectOnSegment(
    ll.LatLng p,
    ll.LatLng a,
    ll.LatLng b,
  ) {
    final cosLat = math.cos(a.latitude * math.pi / 180);
    final bx = (b.longitude - a.longitude) * cosLat;
    final by = b.latitude - a.latitude;
    final px = (p.longitude - a.longitude) * cosLat;
    final py = p.latitude - a.latitude;
    final len2 = bx * bx + by * by;
    final t = len2 == 0 ? 0.0 : ((px * bx + py * by) / len2).clamp(0.0, 1.0);
    final dx = px - bx * t;
    final dy = py - by * t;
    return (t: t, dist: math.sqrt(dx * dx + dy * dy) * _metresPerDegree);
  }

  static double _bearing(ll.LatLng a, ll.LatLng b) {
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}
