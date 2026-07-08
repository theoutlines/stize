import '../models/stop.dart';

abstract class StopsRepository {
  Future<List<Stop>> search(String query);
  Future<List<Stop>> nearby({required double lat, required double lon, double radiusMeters = 500});
}
