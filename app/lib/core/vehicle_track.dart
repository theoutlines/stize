part of 'vehicle_track_animator.dart';

// One animated vehicle ([VehicleTrack]) and one board reading of it
// ([VehicleSample]); [VehicleTrackAnimator] keeps and moves them.

class VehicleTrack {
  VehicleTrack(
    this.to, {
    required this.line,
    required this.type,
    this.heading,
    this.path,
    this.directionRouteId,
    this.source = VehicleSource.live,
  }) : from = to {
    if (path != null) {
      final d = path!.project(to);
      fromDist = d;
      toDist = d;
    }
  }

  ll.LatLng from;
  ll.LatLng to;

  /// Line number and type, carried so the marker can render an informative
  /// badge without re-looking-up the arrival.
  final String line;
  final VehicleType type;

  /// The resolved direction route_id the vehicle travels (see [VehicleSample]).
  /// Held so a follow entered by tapping the marker (which only knows the key)
  /// can still highlight the correct-direction route + stops. Kept across
  /// updates that don't carry it, so a later plain sample can't erase it.
  String? directionRouteId;

  /// Live GPS vs GTFS-schedule-predicted. Scheduled tracks render semi-
  /// transparent; movement is identical (both play the timed plan).
  VehicleSource source;

  /// Travel direction in degrees (0 = north, clockwise), or null if unknown.
  /// Used only as a fallback heading when there's no route [path]; with a path
  /// the heading is derived from the path tangent so it always matches motion.
  double? heading;

  /// The vehicle's route geometry, when known. When present, the marker moves
  /// *along* this path between updates instead of in a straight line (X5).
  RoutePath? path;

  /// Distance-along [path] (metres) the animation eases between. Unused in the
  /// straight-line fallback.
  double fromDist = 0;
  double toDist = 0;

  /// When this vehicle's GPS fix last actually CHANGED, and the fix it was.
  ///
  /// Diagnostics only — nothing reads these to move a marker. `as_of` is the
  /// backend's *last successful fetch*, not the moment the upstream observed the
  /// vehicle, so re-fetching an unchanged board re-stamps it young. The whole
  /// prediction hangs off that stamp, so these two fields measure the difference:
  /// how old the fix REALLY is versus how old the app believes it is.
  DateTime? fixChangedAt;
  ll.LatLng? lastFix;

  /// Time-driven player over the backend's forward timing plan (timed-trajectory
  /// feature). When present it *supersedes* the from/to ease: the marker is
  /// driven forward by wall-clock along the plan instead of easing to the last
  /// fix and stopping. Null when there's no plan (feature off / none usable), in
  /// which case the conservative from/to behaviour above applies unchanged.
  TimedTrajectory? timed;

  /// Wall-clock time of the last update in which the vehicle actually moved.
  /// "Looks stuck" is derived from how long ago this was (time-based, so a burst
  /// of extra refreshes from panning can't make a vehicle read stuck early).
  late DateTime lastMovedAt;

  /// How many consecutive updates the vehicle has been *absent* from the feed.
  /// A short absence is a data blip, not the end of a trip, so the marker is
  /// held (and faded) for a grace period before being dropped (X6).
  int missingCount = 0;
}

/// One vehicle position update fed into [VehicleTrackAnimator.syncSamples].
class VehicleSample {
  const VehicleSample({
    required this.key,
    required this.position,
    required this.line,
    required this.type,
    this.heading,
    this.path,
    this.trajectory,
    this.asOf,
    this.directionRouteId,
    this.source = VehicleSource.live,
  });

  final String key;
  final ll.LatLng position;
  final String line;
  final VehicleType type;
  final double? heading;

  /// The resolved direction route_id this vehicle is travelling (e.g. the
  /// `00079-1` variant, not the bare line `79`). Carried so a follow can draw
  /// the route highlight + its stops for the SAME direction the marker moves
  /// along, instead of the line's default direction (the wrong carriageway).
  final String? directionRouteId;

  /// Live GPS vs GTFS-schedule-predicted (hybrid live+schedule).
  final VehicleSource source;

  /// The vehicle's route geometry, if the caller could resolve it.
  final RoutePath? path;

  /// The backend's forward timing plan and the as-of time it's anchored to. The
  /// caller passes these only when the timed-trajectory feature is on and a plan
  /// is available; the marker then animates by time instead of easing to the
  /// last fix. Requires [path] to be projected onto the road geometry.
  final List<TrajectoryPoint>? trajectory;
  final DateTime? asOf;

  /// The same sample on [p], for a road shape that landed after it was taken.
  VehicleSample withPath(RoutePath p) => VehicleSample(
    key: key,
    position: position,
    line: line,
    type: type,
    heading: heading,
    path: p,
    trajectory: trajectory,
    asOf: asOf,
    directionRouteId: directionRouteId,
    source: source,
  );
}
