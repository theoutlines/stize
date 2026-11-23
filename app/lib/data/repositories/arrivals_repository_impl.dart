import '../../core/offline_schedule.dart';
import '../../domain/models/arrival.dart';
import '../../domain/models/vehicle_type.dart';
import '../../domain/repositories/arrivals_repository.dart';
import '../api/api_exceptions.dart';
import '../api/stigla_api_client.dart';
import '../local/gtfs_offline_cache.dart';

class ArrivalsRepositoryImpl implements ArrivalsRepository {
  ArrivalsRepositoryImpl(this._client, [this._offline]);

  final StiglaApiClient _client;
  final GtfsOfflineCache? _offline;
  Map<String, dynamic>? _scheduleMeta;

  @override
  Future<ArrivalsBoard> getArrivals(String stopId) async {
    try {
      // No cache-buster: ride the backend SWR cache. A `cb=<millis>` query makes
      // every 30s poll a unique key that BYPASSES the SWR cache and forces a fresh
      // upstream fetch, so this surface hangs (10s client timeout) the moment the
      // upstream source is slow. Riding SWR serves the last good board as stale
      // during an upstream blip instead of failing. (Prod incident 2026-07-21.)
      final json = await _client.getJson('/api/v1/arrivals', {'stop': stopId});
      return ArrivalsBoard.fromJson(json);
    } on NotFoundException {
      rethrow;
    } catch (e) {
      // The API worker didn't answer (network, quota exhausted, 5xx): fall back
      // to the stop's static timetable, which is served without the worker.
      if (e is! NetworkException &&
          e is! RateLimitedException &&
          !(e is ApiException && e.statusCode >= 500)) {
        rethrow;
      }
      final board = await _timetableBoard(stopId);
      if (board == null) rethrow;
      return board;
    }
  }

  Future<ArrivalsBoard?> _timetableBoard(String stopId) async {
    try {
      final meta = _scheduleMeta ??= await _client.getJson(
        '/gtfs/schedule/_meta.json',
      );
      final schedule = await _client.getJson(
        '/gtfs/schedule/${Uri.encodeComponent(stopId)}.json',
      );
      final planned = upcomingScheduled(
        schedule,
        meta,
        belgradeNow(DateTime.now()),
      );

      var stopName = stopId;
      final types = <String, VehicleType>{};
      final offline = _offline;
      if (offline != null) {
        for (final s in await offline.getStops()) {
          if (s.stopId == stopId) {
            stopName = s.name;
            break;
          }
        }
        for (final l in await offline.getLines()) {
          types[l.line] = l.vehicleType;
        }
      }
      return ArrivalsBoard(
        stopId: stopId,
        stopName: stopName,
        updatedAt: DateTime.now(),
        serviceStatus: ServiceStatus.unavailable,
        arrivals: [
          for (final p in planned)
            Arrival(
              line: p.line,
              vehicleType: types[p.line] ?? VehicleType.bus,
              etaMinutes: p.etaMinutes,
              stopsRemaining: null,
              routeId: p.routeId,
              directionRouteId: p.routeId,
              gps: null,
              garageNo: null,
              scheduled: true,
            ),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}
