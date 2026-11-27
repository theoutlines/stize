import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/map/route_shape_cache.dart';
import 'package:stize/core/route_path.dart';

void main() {
  final t0 = DateTime(2026, 11, 27, 12);
  final path = RoutePath.fromLatLon(const [
    [44.81, 20.46],
    [44.82, 20.47],
  ]);

  test('each key is claimed once, duplicates folded', () {
    final c = RouteShapeCache();
    expect(c.claim(['79', '79', '2'], t0), ['79', '2']);
    expect(c.claim(['79', '2', '7'], t0), ['7'], reason: 'in flight');
  });

  test('a resolved key is never fetched again, "no shape" included', () {
    final c = RouteShapeCache();
    c.claim(['79', 'Ada 4'], t0);
    c.resolved('79', path);
    c.resolved('Ada 4', null);
    expect(c['79'], same(path));
    expect(c.has('Ada 4'), isTrue);
    expect(c['Ada 4'], isNull);
    expect(c.claim(['79', 'Ada 4'], t0.add(const Duration(hours: 1))), isEmpty);
  });

  test('a failure is retried after retryAfter, not before', () {
    final c = RouteShapeCache(retryAfter: const Duration(seconds: 30));
    c.claim(['79'], t0);
    c.failed('79', t0);
    expect(c.has('79'), isFalse);
    expect(c.claim(['79'], t0.add(const Duration(seconds: 29))), isEmpty);
    expect(c.claim(['79'], t0.add(const Duration(seconds: 30))), ['79']);
  });

  test('a path known from elsewhere is stored as is', () {
    final c = RouteShapeCache();
    c.put('7', path);
    expect(c['7'], same(path));
    expect(c.claim(['7'], t0), isEmpty);
  });
}
