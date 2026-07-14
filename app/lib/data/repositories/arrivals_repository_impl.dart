import '../../domain/models/arrival.dart';
import '../../domain/repositories/arrivals_repository.dart';
import '../api/stigla_api_client.dart';

class ArrivalsRepositoryImpl implements ArrivalsRepository {
  ArrivalsRepositoryImpl(this._client);

  final StiglaApiClient _client;

  @override
  Future<ArrivalsBoard> getArrivals(String stopId) async {
    final json = await _client.getJson('/api/v1/arrivals', {
      'stop': stopId,
      // Cache-buster so the stop screen's 30s poll re-reads live arrivals from
      // the origin instead of a stale browser/zone HTTP cache (Browser Cache TTL
      // gotcha); backend also sets no-store.
      'cb': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    return ArrivalsBoard.fromJson(json);
  }
}
