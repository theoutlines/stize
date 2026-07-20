import 'package:latlong2/latlong.dart' as ll;

import '../domain/models/jam.dart';
import 'route_path.dart';

/// Pure geometry for the tram-jam red segment, kept Flutter-free so it unit-tests
/// without a harness (mirrors route_path.dart / vehicle_track_animator.dart).
///
/// The worker hands us a jam's bounding stops (rear vehicle's last stop → front
/// vehicle's next stop) and the frozen vehicles' positions. Here we project them
/// onto the *direction shape* and either:
///   • return the red segment polyline (that stretch of the shape), or
///   • fail the **geometry gate** and return none — the same honesty rule as
///     stop-dwell for lines 26/27/44, whose GTFS shape runs 77–721 m off the
///     real stops. Drawing a red segment on such a shape would paint the wrong
///     street, so the caller degrades to a badge on the vehicle markers instead.

/// Max perpendicular offset (metres) a jam's anchor points may sit off the shape
/// before we refuse to draw the segment. Healthy shapes carry their stops at ~0 m;
/// the off-shape lines fail this by hundreds of metres. Matches the order of
/// RoutePath's own local-match tolerance.
const double kJamGeometryToleranceM = 60.0;

class JamSegment {
  const JamSegment({required this.polyline, required this.gated});

  /// The red segment to draw along the route, or null when gated / unavailable.
  final List<ll.LatLng>? polyline;

  /// True when the geometry gate rejected the shape (off-shape line): the caller
  /// must NOT draw a segment and should badge the vehicle markers instead.
  final bool gated;

  static const none = JamSegment(polyline: null, gated: false);
}

/// Build the red segment for [jam] along its direction [path], or gate it.
/// Returns [JamSegment.none] when there's no segment info at all (badges, no gate
/// message needed); returns `gated: true` when the shape is off the real stops.
JamSegment buildJamSegment(
  Jam jam,
  RoutePath? path, {
  double tolerance = kJamGeometryToleranceM,
}) {
  final rear = jam.segmentRear;
  final front = jam.segmentFront;
  if (path == null || !path.isUsable || rear == null || front == null) {
    return JamSegment.none;
  }

  // Geometry gate: every anchor (bounding stops + each frozen vehicle) must sit
  // close to the shape. One far-off point means the shape doesn't represent where
  // this jam actually is — degrade to badges rather than paint the wrong street.
  final anchors = <ll.LatLng>[rear, front, for (final v in jam.vehicles) v.position];
  for (final a in anchors) {
    if (path.offsetOf(a) > tolerance) {
      return const JamSegment(polyline: null, gated: true);
    }
  }

  final d0 = path.project(rear);
  final d1 = path.project(front, near: d0);
  final poly = path.subPath(d0, d1);
  if (poly.length < 2) return JamSegment.none;
  return JamSegment(polyline: poly, gated: false);
}

/// Tolerance (metres) so a vehicle sitting right at the jam's tail isn't read as
/// "already past it" by GPS noise.
const double kJamAheadToleranceM = 25.0;

/// Default radius (metres) for "near the user" relevance — roughly the Nearby
/// list's reach, so a jam physically around the user counts as relevant.
const double kJamRelevanceRadiusM = 1500.0;

const ll.Distance _jamDistance = ll.Distance();

/// Whether [jam] is relevant to the user's current context — used to decide
/// whether the jam-mode button shows its loud red count or stays quiet. Relevant
/// when the jam is on the followed vehicle's line, touches the open stop, or sits
/// within [radiusM] of the user. A jam elsewhere in the city is NOT relevant (the
/// button still appears, but muted — it shouldn't nag).
bool isJamRelevant(
  Jam jam, {
  String? followedLine,
  String? openStopId,
  ll.LatLng? userLocation,
  double radiusM = kJamRelevanceRadiusM,
}) {
  if (followedLine != null && jam.line.toLowerCase() == followedLine.toLowerCase()) {
    return true;
  }
  if (openStopId != null && jam.affectedStopIds.contains(openStopId)) return true;
  if (userLocation != null) {
    final pts = <ll.LatLng>[
      for (final v in jam.vehicles) v.position,
      if (jam.segmentFront != null) jam.segmentFront!,
      if (jam.segmentRear != null) jam.segmentRear!,
    ];
    for (final p in pts) {
      if (_jamDistance(userLocation, p) <= radiusM) return true;
    }
  }
  return false;
}

/// Whether [jam] lies AHEAD of a vehicle travelling [vehicleDirectionRouteId] at
/// along-track distance [vehicleAlong] on its direction [path]. True only when:
///   • the jam is on the SAME direction (opposite direction → false), and
///   • some part of the jam (its farthest-along anchor) is still ahead of the
///     vehicle (a jam already fully behind → false).
/// This gates the follow warning so a vehicle on the return leg, or one that has
/// already cleared the stalled stretch, stays silent.
bool isJamAhead({
  required Jam jam,
  required String? vehicleDirectionRouteId,
  required RoutePath? path,
  required double vehicleAlong,
}) {
  if (jam.directionRouteId == null || vehicleDirectionRouteId == null) return false;
  if (jam.directionRouteId != vehicleDirectionRouteId) return false;
  if (path == null || !path.isUsable) return false;
  final anchors = <ll.LatLng>[
    if (jam.segmentFront != null) jam.segmentFront!,
    if (jam.segmentRear != null) jam.segmentRear!,
    for (final v in jam.vehicles) v.position,
  ];
  if (anchors.isEmpty) return false;
  var maxAlong = double.negativeInfinity;
  for (final a in anchors) {
    final along = path.project(a, near: vehicleAlong);
    if (along > maxAlong) maxAlong = along;
  }
  return maxAlong > vehicleAlong + kJamAheadToleranceM;
}
