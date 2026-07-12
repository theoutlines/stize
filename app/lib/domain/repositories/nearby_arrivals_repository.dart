import '../models/nearby_arrival.dart';

abstract class NearbyArrivalsRepository {
  /// Lines you can catch from around a point, grouped by line + direction with
  /// the soonest departures at the nearest serving stop (the "Nearby" list).
  /// Throws [NetworkException] on connectivity failure so the screen can show
  /// its offline state (live data has no meaningful offline fallback).
  Future<List<NearbyGroup>> nearby({
    required double lat,
    required double lon,
    double radiusMeters,
  });
}
