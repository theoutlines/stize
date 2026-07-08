import 'package:latlong2/latlong.dart' as ll;

import '../domain/models/arrival.dart';

class VehicleTrack {
  VehicleTrack(this.to) : from = to;
  ll.LatLng from;
  ll.LatLng to;
}

/// Pure interpolation logic behind the live-tracking map, kept separate from
/// the widget tree so it can be unit-tested without spinning up FlutterMap
/// (which would otherwise mean real tile-server network calls in tests).
///
/// Rule: a vehicle's displayed position only ever eases from wherever it
/// currently sits toward the most recently known *real* GPS fix. It never
/// jumps backward, and never runs past the latest known position.
class VehicleTrackAnimator {
  final Map<String, VehicleTrack> _tracks = {};

  Map<String, VehicleTrack> get tracks => _tracks;

  static String keyFor(Arrival a) => a.garageNo ?? '${a.line}-${a.routeId}';

  /// Call when new arrivals data lands. [currentT] is the animation
  /// controller's value (0..1) *before* it gets reset, so an in-flight
  /// vehicle's current interpolated spot becomes its new starting point.
  void sync(List<Arrival> arrivals, double currentT) {
    final seen = <String>{};
    for (final a in arrivals) {
      final gps = a.gps;
      if (gps == null) continue;
      final key = keyFor(a);
      seen.add(key);
      final newPos = ll.LatLng(gps.lat, gps.lon);
      final existing = _tracks[key];
      if (existing == null) {
        _tracks[key] = VehicleTrack(newPos);
      } else {
        existing.from = _interpolate(existing.from, existing.to, currentT);
        existing.to = newPos;
      }
    }
    _tracks.removeWhere((key, _) => !seen.contains(key));
  }

  ll.LatLng positionOf(String key, double t) {
    final track = _tracks[key]!;
    return _interpolate(track.from, track.to, t);
  }

  Iterable<MapEntry<String, ll.LatLng>> currentPositions(double t) {
    return _tracks.keys.map((key) => MapEntry(key, positionOf(key, t)));
  }

  static ll.LatLng _interpolate(ll.LatLng from, ll.LatLng to, double t) {
    final clampedT = t.clamp(0.0, 1.0);
    return ll.LatLng(
      from.latitude + (to.latitude - from.latitude) * clampedT,
      from.longitude + (to.longitude - from.longitude) * clampedT,
    );
  }
}
