import '../../domain/models/idea.dart';
import '../../domain/repositories/ideas_repository.dart';
import '../api/stigla_api_client.dart';
import '../device/device_id_service.dart';

class IdeasRepositoryImpl implements IdeasRepository {
  IdeasRepositoryImpl(this._client, this._deviceIdService);

  final StiglaApiClient _client;
  final DeviceIdService _deviceIdService;

  Future<Map<String, String>> _deviceHeaders() async {
    return {'X-Device-Id': await _deviceIdService.getOrCreate()};
  }

  @override
  Future<List<Idea>> list() async {
    final headers = await _deviceHeaders();
    final json = await _client.getJson('/api/v1/ideas', null, headers);
    return (json['ideas'] as List<dynamic>).map((e) => Idea.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<Idea> submit(String text) async {
    final headers = await _deviceHeaders();
    final json = await _client.postJson('/api/v1/ideas', body: {'text': text}, headers: headers);
    return Idea.fromJson(json);
  }

  @override
  Future<({int votes, bool hasVoted})> toggleVote(int ideaId) async {
    final headers = await _deviceHeaders();
    final json = await _client.postJson('/api/v1/ideas/$ideaId/vote', headers: headers);
    return (votes: json['votes'] as int, hasVoted: json['has_voted'] as bool);
  }

  @override
  Future<List<IdeaComment>> listComments(int ideaId) async {
    final json = await _client.getJson('/api/v1/ideas/$ideaId/comments');
    return (json['comments'] as List<dynamic>)
        .map((e) => IdeaComment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<IdeaComment> addComment(int ideaId, String text) async {
    final headers = await _deviceHeaders();
    final json = await _client.postJson('/api/v1/ideas/$ideaId/comments', body: {'text': text}, headers: headers);
    return IdeaComment.fromJson(json);
  }
}
