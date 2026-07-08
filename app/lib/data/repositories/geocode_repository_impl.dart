import '../../domain/models/geocode_result.dart';
import '../../domain/repositories/geocode_repository.dart';
import '../api/stigla_api_client.dart';

class GeocodeRepositoryImpl implements GeocodeRepository {
  GeocodeRepositoryImpl(this._client);

  final StiglaApiClient _client;

  @override
  Future<List<GeocodeResult>> search(String query) async {
    final json = await _client.getJson('/api/v1/geocode', {'query': query});
    return (json['results'] as List<dynamic>)
        .map((e) => GeocodeResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
