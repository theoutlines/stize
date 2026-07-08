import '../../domain/models/route_alert.dart';
import '../../domain/repositories/alerts_repository.dart';
import '../api/stigla_api_client.dart';

class AlertsRepositoryImpl implements AlertsRepository {
  AlertsRepositoryImpl(this._client);

  final StiglaApiClient _client;

  @override
  Future<List<RouteAlert>> list() async {
    final json = await _client.getJson('/api/v1/alerts');
    return (json['alerts'] as List<dynamic>)
        .map((e) => RouteAlert.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
