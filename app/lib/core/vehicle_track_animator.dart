import 'package:latlong2/latlong.dart' as ll;

import '../domain/models/arrival.dart';
import '../domain/models/vehicle_type.dart';

class VehicleTrack {
  VehicleTrack(this.to, {required this.line, required this.type})
    : from = to;
  ll.LatLng from;
  ll.LatLng to;

  /// Line number and type, carried so the marker can render an informative
  /// badge without re-looking-up the arrival.
  final String line;
  final VehicleType type;

  /// How many *consecutive* provider updates have landed with the vehicle at
  /// (essentially) the same real position. Movement resets it to 0. This is a
  /// soft "looks stuck" heuristic, not a hard traffic signal.
  int staleCount = 0;
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

  // A vehicle whose reported position hasn't moved beyond this many degrees
  // between updates (~11 m) is treated as not having moved.
  static const _stillEpsilon = 1e-4;

  // Consecutive no-move updates before we call a vehicle "looks stuck".
  static const _stuckThreshold = 2;

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
        _tracks[key] = VehicleTrack(
          newPos,
          line: a.line,
          type: a.vehicleType,
        );
      } else {
        // Movement heuristic compares the new *real* fix against the previous
        // one (existing.to), before we overwrite it.
        if (_isSamePlace(existing.to, newPos)) {
          existing.staleCount++;
        } else {
          existing.staleCount = 0;
        }
        existing.from = _interpolate(existing.from, existing.to, currentT);
        existing.to = newPos;
      }
    }
    _tracks.removeWhere((key, _) => !seen.contains(key));
  }

  /// Whether a vehicle currently reads as stuck (hasn't moved across the last
  /// [_stuckThreshold] updates). Unknown keys are treated as moving.
  bool isStuck(String key) =>
      (_tracks[key]?.staleCount ?? 0) >= _stuckThreshold;

  VehicleTrack? trackFor(String key) => _tracks[key];

  static bool _isSamePlace(ll.LatLng a, ll.LatLng b) =>
      (a.latitude - b.latitude).abs() < _stillEpsilon &&
      (a.longitude - b.longitude).abs() < _stillEpsilon;

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
