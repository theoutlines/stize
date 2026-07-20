import 'package:latlong2/latlong.dart' as ll;

/// Tram-jam ("stalled segment") detection, served by GET /api/v1/jams. The worker
/// keeps a light last-fix table and hands us the current jam set; the geometry
/// (projecting the red segment onto the direction shape + the geometry gate) is
/// done client-side. See docs/reports/2026-07-20-jam-detection.md.

class JamVehicle {
  const JamVehicle({
    required this.garageNo,
    required this.position,
    required this.stopsRemaining,
    required this.frozenSecs,
    required this.isSubstitute,
  });

  final String garageNo;
  final ll.LatLng position;
  final int? stopsRemaining;
  final int frozenSecs;
  final bool isSubstitute;

  factory JamVehicle.fromJson(Map<String, dynamic> j) => JamVehicle(
        garageNo: j['garage_no'] as String,
        position: ll.LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
        stopsRemaining: (j['stops_remaining'] as num?)?.toInt(),
        frozenSecs: (j['frozen_secs'] as num).toInt(),
        isSubstitute: j['is_substitute'] == true,
      );
}

class Jam {
  const Jam({
    required this.line,
    required this.directionRouteId,
    required this.vehicles,
    required this.frozenSecs,
    required this.hasSubstitute,
    required this.segmentRear,
    required this.segmentFront,
    required this.affectedStopIds,
    required this.simulated,
  });

  final String line;
  final String? directionRouteId;
  final List<JamVehicle> vehicles;
  final int frozenSecs;
  final bool hasSubstitute;

  /// Stop coords bounding the stalled span (rear vehicle's last stop → front
  /// vehicle's next stop). Null when the direction shape is unavailable — the
  /// client then shows marker badges only, no red segment.
  final ll.LatLng? segmentRear;
  final ll.LatLng? segmentFront;

  /// Stops the jam affects: WITHIN the stalled span (under the red segment) plus
  /// the downstream stops ahead of it. Both the delay banner and the stop glow
  /// key off this set. (Round-2 fix: within-span stops used to be omitted.)
  final Set<String> affectedStopIds;

  final bool simulated;

  factory Jam.fromJson(Map<String, dynamic> j) {
    final seg = j['segment'] as Map<String, dynamic>?;
    ll.LatLng? coord(Object? o) {
      final m = o as Map<String, dynamic>?;
      if (m == null) return null;
      return ll.LatLng((m['lat'] as num).toDouble(), (m['lon'] as num).toDouble());
    }

    return Jam(
      line: j['line'] as String,
      directionRouteId: j['direction_route_id'] as String?,
      vehicles: ((j['vehicles'] as List<dynamic>?) ?? const [])
          .map((e) => JamVehicle.fromJson(e as Map<String, dynamic>))
          .toList(),
      frozenSecs: (j['frozen_secs'] as num).toInt(),
      hasSubstitute: j['has_substitute'] == true,
      segmentRear: coord(seg?['rear']),
      segmentFront: coord(seg?['front']),
      affectedStopIds:
          ((j['affected_stop_ids'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toSet(),
      simulated: j['simulated'] == true,
    );
  }
}

/// A bus running a tram line, independent of any jam (planned track works also do
/// this). Its own neutral notice; toned down when a route alert already announced it.
class Substitution {
  const Substitution({
    required this.line,
    required this.directionRouteId,
    required this.garageNos,
    required this.simulated,
  });

  final String line;
  final String? directionRouteId;
  final List<String> garageNos;
  final bool simulated;

  factory Substitution.fromJson(Map<String, dynamic> j) => Substitution(
        line: j['line'] as String,
        directionRouteId: j['direction_route_id'] as String?,
        garageNos:
            ((j['garage_nos'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList(),
        simulated: j['simulated'] == true,
      );
}

class JamsBoard {
  const JamsBoard({
    required this.feedHealthy,
    required this.jams,
    required this.substitutions,
  });

  final bool feedHealthy;
  final List<Jam> jams;
  final List<Substitution> substitutions;

  static const empty = JamsBoard(feedHealthy: true, jams: [], substitutions: []);

  /// Active jams shown to the user: only when the feed is healthy (starvation =
  /// nothing). Drives the jam-mode toggle's visibility and count.
  List<Jam> get activeJams => feedHealthy ? jams : const [];

  /// Jams affecting a given line number (any direction).
  List<Jam> jamsForLine(String line) =>
      activeJams.where((j) => j.line.toLowerCase() == line.toLowerCase()).toList();

  /// The jam affecting a given stop (within its stalled span or downstream), if
  /// any — drives the stop-board delay banner and the stop glow.
  Jam? affectedJamAt(String stopId, {String? line}) {
    for (final j in activeJams) {
      if (line != null && j.line.toLowerCase() != line.toLowerCase()) continue;
      if (j.affectedStopIds.contains(stopId)) return j;
    }
    return null;
  }

  /// Every stop id touched by an active jam (for the map glow).
  Set<String> get allAffectedStopIds => {
        for (final j in activeJams) ...j.affectedStopIds,
      };

  factory JamsBoard.fromJson(Map<String, dynamic> j) => JamsBoard(
        feedHealthy: j['feed_healthy'] != false,
        jams: ((j['jams'] as List<dynamic>?) ?? const [])
            .map((e) => Jam.fromJson(e as Map<String, dynamic>))
            .toList(),
        substitutions: ((j['substitutions'] as List<dynamic>?) ?? const [])
            .map((e) => Substitution.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
