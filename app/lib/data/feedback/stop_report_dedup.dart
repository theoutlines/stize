import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which (stop, problem) pairs this device already reported, so the
/// same report is not sent twice within [window]: the sheet shows "Already
/// sent today" instead. Reports from different devices still all arrive.
class StopReportDedup {
  StopReportDedup({this.window = const Duration(hours: 24), DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final Duration window;
  final DateTime Function() _now;

  static String _key(String stopId, String category) =>
      'stop_report:$stopId|$category';

  Future<bool> sentRecently(String stopId, String category) async {
    final prefs = await SharedPreferences.getInstance();
    final at = prefs.getInt(_key(stopId, category));
    if (at == null) return false;
    return _now().difference(DateTime.fromMillisecondsSinceEpoch(at)) < window;
  }

  Future<void> markSent(String stopId, String category) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(stopId, category), _now().millisecondsSinceEpoch);
  }
}
