/// Sends a single in-app feedback message to the backend (`POST /api/v1/feedback`).
/// App version / platform / locale are attached automatically by the caller (the
/// contact email is deliberately never exposed — replies happen out-of-band).
abstract class FeedbackRepository {
  Future<void> submit({
    required String message,
    String? contact,
    required String appVersion,
    required String platform,
    required String locale,
  });
}
