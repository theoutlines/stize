import '../../domain/models/line_info.dart';
import '../../domain/models/route_shape.dart';
import '../../domain/repositories/lines_repository.dart';
import '../api/api_exceptions.dart';
import '../api/stigla_api_client.dart';
import '../local/gtfs_offline_cache.dart';

class LinesRepositoryImpl implements LinesRepository {
  LinesRepositoryImpl(this._client, this._offlineCache);

  final StiglaApiClient _client;
  final GtfsOfflineCache _offlineCache;

  @override
  Future<List<LineInfo>> search(String query) async {
    try {
      final json = await _client.getJson('/api/v1/lines', {'query': query});
      return (json['lines'] as List<dynamic>)
          .map((e) => LineInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } on NetworkException {
      return _offlineCache.searchLinesOffline(query);
    }
  }

  @override
  Future<RouteShape> getShapeByLineNumber(String line) async {
    final json = await _client.getJson('/api/v1/lines/by-number/${Uri.encodeComponent(line)}/shape');
    return RouteShape.fromJson(json);
  }

  @override
  Future<RouteShape> getShapeByRouteId(String routeId) async {
    final json = await _client.getJson('/api/v1/lines/${Uri.encodeComponent(routeId)}/shape');
    return RouteShape.fromJson(json);
  }
}
