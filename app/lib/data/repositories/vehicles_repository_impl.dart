import '../../domain/models/area_vehicle.dart';
import '../../domain/repositories/vehicles_repository.dart';
import '../api/api_exceptions.dart';
import '../api/stigla_api_client.dart';

class VehiclesRepositoryImpl implements VehiclesRepository {
  VehiclesRepositoryImpl(this._client);

  final StiglaApiClient _client;

  @override
  Future<List<AreaVehicle>> nearby({
    required double lat,
    required double lon,
    double radiusMeters = 800,
  }) async {
    try {
      // No cache-buster: ride the backend SWR cache. A `cb=<millis>` query makes
      // every 30s poll a unique key that BYPASSES the SWR cache and forces a
      // fresh upstream fan-out (≤12 stops), so this surface hangs (10s client
      // timeout → empty) the moment the upstream source is slow. Riding SWR
      // serves the last good fixes as stale during an upstream blip instead of
      // going blank. (Prod incident 2026-07-21.)
      final json = await _client.getJson('/api/v1/vehicles/nearby', {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'radius': radiusMeters.toString(),
      });
      return (json['vehicles'] as List<dynamic>)
          .map((e) => AreaVehicle.fromJson(e as Map<String, dynamic>))
          .toList();
    } on NetworkException {
      return const [];
    }
  }
}
