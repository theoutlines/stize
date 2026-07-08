import '../../domain/models/stop.dart';
import '../../domain/repositories/stops_repository.dart';
import '../api/stigla_api_client.dart';

class StopsRepositoryImpl implements StopsRepository {
  StopsRepositoryImpl(this._client);

  final StiglaApiClient _client;

  @override
  Future<List<Stop>> search(String query) async {
    final json = await _client.getJson('/api/v1/stops', {'query': query});
    return (json['stops'] as List<dynamic>)
        .map((e) => Stop.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Stop>> nearby({required double lat, required double lon, double radiusMeters = 500}) async {
    final json = await _client.getJson('/api/v1/stops/nearby', {
      'lat': lat.toString(),
      'lon': lon.toString(),
      'radius': radiusMeters.toString(),
    });
    return (json['stops'] as List<dynamic>)
        .map((e) => Stop.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
