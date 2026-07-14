/// One waypoint of a vehicle's forward timing plan (timed-trajectory feature):
/// an absolute route position and the seconds *after the plan's as-of time* at
/// which the vehicle is expected to be there. The plan starts at the vehicle's
/// current position ([etaSeconds] 0) and lists the stations ahead of it.
class TrajectoryPoint {
  const TrajectoryPoint(this.lat, this.lon, this.etaSeconds);

  final double lat;
  final double lon;
  final int etaSeconds;

  factory TrajectoryPoint.fromJson(Map<String, dynamic> json) {
    return TrajectoryPoint(
      (json['lat'] as num).toDouble(),
      (json['lon'] as num).toDouble(),
      (json['eta_seconds'] as num).round(),
    );
  }

  /// Parses a `trajectory` JSON array, or null when absent/empty (the field is
  /// additive and flag-gated backend-side, so it's simply missing when off).
  static List<TrajectoryPoint>? listFromJson(dynamic json) {
    if (json is! List || json.isEmpty) return null;
    return json
        .map((e) => TrajectoryPoint.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }
}
