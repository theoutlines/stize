import '../../domain/models/jam.dart';
import '../../domain/repositories/jams_repository.dart';
import '../api/stigla_api_client.dart';

class JamsRepositoryImpl implements JamsRepository {
  JamsRepositoryImpl(this._client);

  final StiglaApiClient _client;

  @override
  Future<JamsBoard> current({String? sim}) async {
    final json = await _client.getJson(
      '/api/v1/jams',
      sim != null ? {'sim': sim} : null,
    );
    return JamsBoard.fromJson(json);
  }
}
