import '../models/geocode_result.dart';

abstract class GeocodeRepository {
  Future<List<GeocodeResult>> search(String query);
}
