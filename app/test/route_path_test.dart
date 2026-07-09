import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:stigla/core/route_path.dart';

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
}
