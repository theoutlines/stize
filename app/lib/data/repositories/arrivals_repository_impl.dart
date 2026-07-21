import '../../domain/models/arrival.dart';
import '../../domain/repositories/arrivals_repository.dart';
import '../api/stigla_api_client.dart';

class ArrivalsRepositoryImpl implements ArrivalsRepository {
  ArrivalsRepositoryImpl(this._client);

  final StiglaApiClient _client;

  @override
  Future<ArrivalsBoard> getArrivals(String stopId) async {
    // No cache-buster: ride the backend SWR cache. A `cb=<millis>` query makes
    // every 30s poll a unique key that BYPASSES the SWR cache and forces a fresh
    // upstream fetch, so this surface hangs (10s client timeout) the moment the
    // upstream source is slow. Riding SWR serves the last good board as stale
    // during an upstream blip instead of failing. (Prod incident 2026-07-21.)
    final json = await _client.getJson('/api/v1/arrivals', {
      'stop': stopId,
    });
    return ArrivalsBoard.fromJson(json);
  }
}
