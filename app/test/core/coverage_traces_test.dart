import 'package:flutter_test/flutter_test.dart';

import 'package:stize/core/coverage_traces.dart';

void main() {
  test('decodes delta-encoded routes into local world units', () {
    final t = CoverageTraces.fromJson({
      'routes': [
        {
          't': 'tram',
          'n': 120,
          'p': [2046000, 4481000, 100, 0],
        },
      ],
    });
    expect(t.traces, hasLength(1));
    final r = t.traces.single;
    expect(r.type, 'tram');
    expect(r.trips, 120);
    expect(r.points, hasLength(4));
    // 0.001° east is ~0.0000028 world units → ~0.28 local units, same y.
    expect(r.points[2] - r.points[0], closeTo(0.278, 0.01));
    expect(r.points[3], closeTo(r.points[1], 1e-3));
  });

  test('world and lon/lat round-trip', () {
    final (x, y) = CoverageTraces.worldOf(20.46, 44.81);
    final (lon, lat) = CoverageTraces.lonLatOf(x, y);
    expect(lon, closeTo(20.46, 1e-9));
    expect(lat, closeTo(44.81, 1e-9));
  });
}
