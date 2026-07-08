import '../../domain/models/arrival.dart';
import '../../domain/repositories/arrivals_repository.dart';
import '../api/stigla_api_client.dart';

class ArrivalsRepositoryImpl implements ArrivalsRepository {
  ArrivalsRepositoryImpl(this._client);

  final StiglaApiClient _client;

  @override
  Future<ArrivalsBoard> getArrivals(String stopId) async {
    final json = await _client.getJson('/api/v1/arrivals', {'stop': stopId});
    return ArrivalsBoard.fromJson(json);
  }
}
