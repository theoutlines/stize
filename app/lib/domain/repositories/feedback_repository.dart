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

  /// Reports wrong data at one stop (`POST /api/v1/stops/:id/report`).
  /// [category] is one of the backend's closed list; [comment] only with
  /// `other`. No location or identity is sent: the server adds the stop's
  /// position and lines itself.
  Future<void> submitStopReport({
    required String stopId,
    required String category,
    String? comment,
    required String appVersion,
    required String platform,
    required String locale,
  });
}
