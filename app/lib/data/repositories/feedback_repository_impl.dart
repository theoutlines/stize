import '../../domain/repositories/feedback_repository.dart';
import '../api/stigla_api_client.dart';
import '../device/device_id_service.dart';

class FeedbackRepositoryImpl implements FeedbackRepository {
  FeedbackRepositoryImpl(this._client, this._deviceIdService);

  final StiglaApiClient _client;
  final DeviceIdService _deviceIdService;

  @override
  Future<void> submit({
    required String message,
    String? contact,
    required String appVersion,
    required String platform,
    required String locale,
  }) async {
    final headers = {'X-Device-Id': await _deviceIdService.getOrCreate()};
    await _client.postJson(
      '/api/v1/feedback',
      body: {
        'message': message,
        if (contact != null && contact.trim().isNotEmpty)
          'contact': contact.trim(),
        'app_version': appVersion,
        'platform': platform,
        'locale': locale,
      },
      headers: headers,
    );
  }
}
