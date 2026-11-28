import 'dart:convert';
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

  /// The routes as a GeoJSON FeatureCollection of LineStrings with `type`
  /// and `trips`, for the map's own line layers.
  String toGeoJson() {
    double r5(double v) => (v * 1e5).roundToDouble() / 1e5;
    final features = [
      for (final t in traces)
        {
          'type': 'Feature',
          'properties': {'type': t.type, 'trips': t.trips},
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              for (var i = 0; i + 1 < t.points.length; i += 2)
                () {
                  final (lon, lat) = lonLatOf(
                    t.points[i] / unit + origin.$1,
                    t.points[i + 1] / unit + origin.$2,
                  );
                  return [r5(lon), r5(lat)];
                }(),
            ],
          },
        },
    ];
    return jsonEncode({'type': 'FeatureCollection', 'features': features});
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
