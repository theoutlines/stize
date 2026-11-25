import 'dart:math' as math;

/// Remembers where each live vehicle (by garage number) was last seen moving,
/// fed by every arrivals board the app loads. A vehicle whose reported
/// position has not changed for [stuckAfter] reads as stuck: the card drops its
/// pulsing dot and its times turn approximate ("≈ 8 min").
///
/// Same threshold as the map's track animator, so the board and the map agree.
class MovementTracker {
  MovementTracker({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// The app-wide tracker (boards and Nearby share what they have seen).
  static final MovementTracker instance = MovementTracker();

  static const Duration stuckAfter = Duration(minutes: 2);

  /// A fix within this distance of the last one is "the same place".
  static const double stillMeters = 25;

  /// Entries not refreshed for this long are dropped.
  static const Duration _forgetAfter = Duration(minutes: 20);

  final DateTime Function() _clock;
  final Map<String, _Seen> _seen = {};

  /// Record a position fix for [key] as of [at] (the board's own timestamp,
  /// so a cached board doesn't count as fresh motion).
  void observe(String key, double lat, double lon, {DateTime? at}) {
    final now = at ?? _clock();
    final prev = _seen[key];
    if (prev == null || _meters(prev.lat, prev.lon, lat, lon) > stillMeters) {
      _seen[key] = _Seen(lat, lon, now, now);
    } else if (now.isAfter(prev.lastSeen)) {
      prev.lastSeen = now;
    }
    _prune(now);
  }

  /// How long [key] has stood still as far as the feed shows, or null when we
  /// have never seen it.
  Duration? stillFor(String key) {
    final s = _seen[key];
    if (s == null) return null;
    final d = s.lastSeen.difference(s.since);
    return d.isNegative ? Duration.zero : d;
  }

  bool isStuck(String? key) {
    if (key == null) return false;
    final d = stillFor(key);
    return d != null && d >= stuckAfter;
  }

  void _prune(DateTime now) {
    if (_seen.length < 400) return;
    _seen.removeWhere((_, s) => now.difference(s.lastSeen) > _forgetAfter);
  }

  static double _meters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }
}

class _Seen {
  _Seen(this.lat, this.lon, this.since, this.lastSeen);
  final double lat;
  final double lon;

  /// When the vehicle arrived at this place (its last real move).
  final DateTime since;

  /// The latest fix that still put it here.
  DateTime lastSeen;
}
