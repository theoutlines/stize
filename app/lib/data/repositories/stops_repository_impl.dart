import '../../domain/models/stop.dart';
import '../../domain/repositories/stops_repository.dart';
import '../api/api_exceptions.dart';
import '../api/stigla_api_client.dart';
import '../local/gtfs_offline_cache.dart';

class StopsRepositoryImpl implements StopsRepository {
  StopsRepositoryImpl(this._client, this._offlineCache);

  final StiglaApiClient _client;
  final GtfsOfflineCache _offlineCache;

  @override
  Future<List<Stop>> search(String query) async {
    try {
      final json = await _client.getJson('/api/v1/stops', {'query': query});
      return (json['stops'] as List<dynamic>)
          .map((e) => Stop.fromJson(e as Map<String, dynamic>))
          .toList();
    } on NetworkException {
      return _offlineCache.searchStopsOffline(query);
    }
  }

  @override
  Future<List<Stop>> nearby({required double lat, required double lon, double radiusMeters = 500}) async {
    try {
      final json = await _client.getJson('/api/v1/stops/nearby', {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'radius': radiusMeters.toString(),
      });
      return (json['stops'] as List<dynamic>)
          .map((e) => Stop.fromJson(e as Map<String, dynamic>))
          .toList();
    } on NetworkException {
      return _offlineCache.nearbyOffline(lat, lon, radiusMeters);
    }
  }
}
