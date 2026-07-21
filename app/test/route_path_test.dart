import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:stize/core/route_path.dart';

void main() {
  // An L-shaped route: A -> B goes east, B -> C goes north.
  final path = RoutePath.fromLatLon([
    [44.80, 20.50], // A
    [44.80, 20.52], // B (east of A)
    [44.81, 20.52], // C (north of B)
  ])!;

  test('endpoints and length', () {
    expect(path.isUsable, isTrue);
    expect(path.pointAt(0).latitude, closeTo(44.80, 1e-9));
    expect(path.pointAt(0).longitude, closeTo(20.50, 1e-9));
    final end = path.pointAt(path.length);
    expect(end.latitude, closeTo(44.81, 1e-6));
    expect(end.longitude, closeTo(20.52, 1e-6));
  });

  test('project returns distance-along of the nearest point', () {
    // A point just south of the mid of segment A->B projects onto that segment.
    final d = path.project(const ll.LatLng(44.799, 20.51));
    // Halfway along A->B is ~ half of that segment's length; comfortably less
    // than the corner B.
    final atB = path.project(const ll.LatLng(44.80, 20.52));
    expect(d, greaterThan(0));
    expect(d, lessThan(atB));
  });

  test('pointAt mid-distance follows the route, not a diagonal shortcut', () {
    // The first leg (A->B, east) is longer than the second, so the distance
    // midpoint sits ON that leg: latitude still 44.80, NOT the diagonal midpoint
    // (44.805) a straight A->C line would produce.
    final mid = path.pointAt(path.length / 2);
    expect(mid.latitude, closeTo(44.80, 1e-4));
    expect(mid.longitude, greaterThan(20.505));
  });

  test('heading is east on the first leg, north on the second', () {
    expect(path.headingAt(1), closeTo(90, 1)); // due east
    expect(path.headingAt(path.length - 1), closeTo(0, 1)); // due north
    // Reversed travel flips it.
    expect(path.headingAt(1, forward: false), closeTo(270, 1));
  });

  group('windowed projection on a fold-back route (F1)', () {
    // An out-and-back: east along ~44.800, then back west along ~44.8003, a
    // hair (~33 m) to the north. The outbound and return legs run parallel and
    // close, so a fix on the return leg is geometrically near BOTH legs.
    final outAndBack = RoutePath.fromLatLon([
      [44.8000, 20.5000], // A  outbound start
      [44.8000, 20.5200], // B  outbound end (east)
      [44.8003, 20.5200], // B' return start (just north of B)
      [44.8003, 20.5000], // A' return end (west)
    ])!;

    // Distance-along at the midpoint of the return leg (its last segment runs
    // from B' at 20.5200 back to A' at 20.5000).
    final returnStart = outAndBack.project(const ll.LatLng(44.8003, 20.5200));
    final returnMid = (returnStart + outAndBack.length) / 2;
    // A fix a hair closer to the outbound leg (lat 44.80008 vs 44.8000 / 44.8003).
    const nearOutbound = ll.LatLng(44.80008, 20.5100);

    test('with no anchor, an ambiguous fix snaps to the nearest (outbound) leg',
        () {
      final d = outAndBack.project(nearOutbound);
      // Outbound is the first segment, so its along-distance is in the first half.
      expect(d, lessThan(outAndBack.length / 2));
    });

    test('a return-leg anchor pulls the same fix onto the return leg', () {
      final d = outAndBack.project(nearOutbound, near: returnMid);
      expect(d, greaterThan(outAndBack.length / 2));
    });

    test('a genuine far jump still falls back to the global nearest', () {
      // Fix sits squarely ON the outbound leg (perp distance ~0 there) but the
      // anchor is stale at the very end: no in-window candidate is anywhere near
      // the fix, so the global match wins instead of crawling along the route.
      const withGlobal = ll.LatLng(44.8000, 20.5150);
      final d = outAndBack.project(withGlobal, near: outAndBack.length);
      expect(d, closeTo(outAndBack.project(withGlobal), 1));
      expect(d, lessThan(outAndBack.length / 2));
    });
  });

  group('headingAtSmoothed (continuous bearing through curves)', () {
    // Reuse the L-shaped path: east leg (bearing ~90) then north leg (~0).
    final corner = path.project(const ll.LatLng(44.80, 20.52));

    test('matches the segment heading on a straight run', () {
      // Well inside the east leg, away from any bend, the look-ahead chord is
      // colinear with the segment — so smoothed ≈ per-segment.
      expect(
        path.headingAtSmoothed(corner / 2, lookahead: 30),
        closeTo(path.headingAt(corner / 2), 0.5),
      );
    });

    test('begins turning before a corner instead of snapping at it', () {
      final near = corner - 15; // 15 m before the bend
      // The per-segment bearing is still exactly the east leg (no turn yet)...
      expect(path.headingAt(near), closeTo(90, 1));
      // ...but the look-ahead chord already reaches into the north leg, so the
      // smoothed bearing has started rotating east→north (a value strictly
      // between the two legs) — a continuous turn, not a vertex-to-vertex jump.
      final smoothed = path.headingAtSmoothed(near, lookahead: 40);
      expect(smoothed, lessThan(89));
      expect(smoothed, greaterThan(1));
    });

    test('reverses by 180° when travelling the path backward', () {
      final fwd = path.headingAtSmoothed(corner / 2, forward: true);
      final back = path.headingAtSmoothed(corner / 2, forward: false);
      expect((back - (fwd + 180) % 360).abs(), lessThan(1));
    });
  });
}
