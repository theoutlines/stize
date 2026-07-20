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
