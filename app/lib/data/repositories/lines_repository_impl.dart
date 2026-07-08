import '../../domain/models/line_info.dart';
import '../../domain/repositories/lines_repository.dart';
import '../api/stigla_api_client.dart';

class LinesRepositoryImpl implements LinesRepository {
  LinesRepositoryImpl(this._client);

  final StiglaApiClient _client;

  @override
  Future<List<LineInfo>> search(String query) async {
    final json = await _client.getJson('/api/v1/lines', {'query': query});
    return (json['lines'] as List<dynamic>)
        .map((e) => LineInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
