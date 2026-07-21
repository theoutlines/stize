import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:stize/data/api/stigla_api_client.dart';
import 'package:stize/data/local/gtfs_offline_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'gtfs_cache_stops_v1': jsonEncode([
        {'stop_id': '20091', 'name': 'Batutova', 'lat': 44.795374, 'lon': 20.499713, 'lines': ['79']},
        {'stop_id': '20097', 'name': 'Batutova', 'lat': 44.795946, 'lon': 20.498157, 'lines': ['5', '7L']},
        {'stop_id': '99999', 'name': 'Far Away Stop', 'lat': 40.0, 'lon': 10.0, 'lines': ['1']},
      ]),
      'gtfs_cache_lines_v1': jsonEncode([
        {
          'line': '79',
          'vehicle_type': 'bus',
          'route_id': '00079',
          'origin': 'Dorćol',
          'destination': 'Mirijevo 4',
        },
      ]),
      'gtfs_cache_fetched_at_v1': DateTime.now().toIso8601String(),
    });
  });

  test('reads cached stops and lines back out', () async {
    final cache = GtfsOfflineCache(StiglaApiClient());
    expect((await cache.getStops()).length, 3);
    expect((await cache.getLines()).length, 1);
  });

  test('searches cached stops by substring, case-insensitively', () async {
    final cache = GtfsOfflineCache(StiglaApiClient());
    final results = await cache.searchStopsOffline('batutova');
    expect(results.length, 2);
    expect(results.every((s) => s.name == 'Batutova'), isTrue);
  });

  test('searches cached lines by substring', () async {
    final cache = GtfsOfflineCache(StiglaApiClient());
    final results = await cache.searchLinesOffline('79');
    expect(results, hasLength(1));
    expect(results.first.origin, 'Dorćol');
  });

  test('finds nearby stops within radius, excluding the far one', () async {
    final cache = GtfsOfflineCache(StiglaApiClient());
    final results = await cache.nearbyOffline(44.795374, 20.499713, 300);
    expect(results.map((s) => s.stopId), containsAll(['20091', '20097']));
    expect(results.map((s) => s.stopId), isNot(contains('99999')));
  });

  test('does not refresh when the cache is still fresh', () async {
    final cache = GtfsOfflineCache(StiglaApiClient());
    // No HTTP call should be attempted; if it were, this would hang/throw in
    // the test environment. Completing at all means the freshness check worked.
    await cache.refreshIfStale();
    expect((await cache.getStops()).length, 3);
  });
}
