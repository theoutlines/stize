import 'dart:math' as math;
import 'dart:typed_data';

/// One city route direction for the Coverage map: its vehicle type (`bus`,
/// `trolleybus`, `tram`), weekday trips and shape in Web Mercator world
/// units (0..1), relative to [CoverageTraces.origin] and scaled by
/// [CoverageTraces.unit] so the numbers stay small (float precision).
class CoverageTrace {
  const CoverageTrace({
    required this.type,
    required this.trips,
    required this.points,
  });

  final String type;
  final int trips;

  /// Flat x0, y0, x1, y1… in local units.
  final Float32List points;

  /// [points] with every vertex dropped that lies within [tolerance] (local
  /// units) of the line kept around it (Douglas–Peucker). At the city view a
  /// pixel spans many vertices; drawing them all is what makes the threads
  /// expensive to stroke on phones.
  Float32List simplified(double tolerance) {
    final n = points.length ~/ 2;
    if (n < 3 || tolerance <= 0) return points;
    final keep = List<bool>.filled(n, false)
      ..[0] = true
      ..[n - 1] = true;
    final t2 = tolerance * tolerance;
    final stack = <int>[0, n - 1];
    while (stack.isNotEmpty) {
      final b = stack.removeLast();
      final a = stack.removeLast();
      final ax = points[2 * a], ay = points[2 * a + 1];
      final dx = points[2 * b] - ax, dy = points[2 * b + 1] - ay;
      final len2 = dx * dx + dy * dy;
      var worst = -1.0;
      var at = -1;
      for (var i = a + 1; i < b; i++) {
        final px = points[2 * i] - ax, py = points[2 * i + 1] - ay;
        double d2;
        if (len2 == 0) {
          d2 = px * px + py * py;
        } else {
          final u = ((px * dx + py * dy) / len2).clamp(0.0, 1.0);
          final ex = px - u * dx, ey = py - u * dy;
          d2 = ex * ex + ey * ey;
        }
        if (d2 > worst) {
          worst = d2;
          at = i;
        }
      }
      if (at >= 0 && worst > t2) {
        keep[at] = true;
        stack
          ..addAll([a, at])
          ..addAll([at, b]);
      }
    }
    final out = Float32List(2 * keep.where((k) => k).length);
    var j = 0;
    for (var i = 0; i < n; i++) {
      if (!keep[i]) continue;
      out[j++] = points[2 * i];
      out[j++] = points[2 * i + 1];
    }
    return out;
  }
}

/// Every route trace (backend `/api/v1/coverage/routes`), ready to draw.
class CoverageTraces {
  CoverageTraces(this.traces);

  /// World point the local units are measured from: central Belgrade.
  static const origin = (0.5568, 0.3594);

  /// Local units per world unit: ~0.6 m per unit at Belgrade's latitude.
  static const unit = 1e5;

  final List<CoverageTrace> traces;

  /// Decodes the backend's delta-encoded `{routes: [{t, n, p}]}`.
  factory CoverageTraces.fromJson(Map<String, dynamic> json) {
    final out = <CoverageTrace>[];
    for (final r in (json['routes'] as List? ?? const [])) {
      final m = r as Map<String, dynamic>;
      final p = (m['p'] as List).cast<num>();
      final pts = Float32List(p.length);
      var lon = 0;
      var lat = 0;
      for (var i = 0; i + 1 < p.length; i += 2) {
        lon += p[i].toInt();
        lat += p[i + 1].toInt();
        final (x, y) = worldOf(lon / 1e5, lat / 1e5);
        pts[i] = ((x - origin.$1) * unit).toDouble();
        pts[i + 1] = ((y - origin.$2) * unit).toDouble();
      }
      out.add(
        CoverageTrace(
          type: m['t'] as String,
          trips: (m['n'] as num).toInt(),
          points: pts,
        ),
      );
    }
    return CoverageTraces(out);
  }

  /// Web Mercator world coordinates (0..1, y down) of a lon/lat.
  static (double, double) worldOf(double lon, double lat) {
    final x = (lon + 180) / 360;
    final s = math.sin(lat * math.pi / 180);
    final y = 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
    return (x, y);
  }

  /// The lon/lat of a world point.
  static (double, double) lonLatOf(double x, double y) {
    final lon = x * 360 - 180;
    final n = math.pi - 2 * math.pi * y;
    final lat = 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
    return (lon, lat);
  }
}
