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
