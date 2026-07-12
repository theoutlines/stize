import '../../domain/models/nearby_arrival.dart';
import '../../domain/repositories/nearby_arrivals_repository.dart';
import '../api/stigla_api_client.dart';

class NearbyArrivalsRepositoryImpl implements NearbyArrivalsRepository {
  NearbyArrivalsRepositoryImpl(this._client);

  final StiglaApiClient _client;

  @override
  Future<List<NearbyGroup>> nearby({
    required double lat,
    required double lon,
    double radiusMeters = 500,
  }) async {
    // Let NetworkException propagate so the screen can show its offline state —
    // there's no meaningful on-device fallback for live arrivals.
    final json = await _client.getJson('/api/v1/arrivals/nearby', {
      'lat': lat.toString(),
      'lon': lon.toString(),
      'radius': radiusMeters.toString(),
    });
    return (json['groups'] as List<dynamic>)
        .map((e) => NearbyGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
