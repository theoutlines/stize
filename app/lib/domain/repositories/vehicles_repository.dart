import '../models/area_vehicle.dart';

abstract class VehiclesRepository {
  /// Live vehicles physically inside the given area. Best-effort: returns an
  /// empty list on a network failure (there's no meaningful offline fallback
  /// for live positions).
  Future<List<AreaVehicle>> nearby({
    required double lat,
    required double lon,
    double radiusMeters,
  });
}
