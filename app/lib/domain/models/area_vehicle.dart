import 'trajectory_point.dart';
import 'vehicle_source.dart';
import 'vehicle_type.dart';

/// A single moving vehicle shown on the map's "transport in the visible area"
/// view. Reconstructed backend-side from per-stop arrivals; carries a
/// route-derived travel [heading] (degrees, 0 = north, clockwise).
class AreaVehicle {
  const AreaVehicle({
    required this.line,
    required this.vehicleType,
    required this.garageNo,
    required this.lat,
    required this.lon,
    required this.heading,
    this.trajectory,
    this.asOf,
    this.source = VehicleSource.live,
    this.tripId,
    this.routeId,
  });

  final String line;
  final VehicleType vehicleType;
  final String? garageNo;
  final double lat;
  final double lon;
  final double? heading;

  /// Live GPS vs GTFS-schedule-predicted (hybrid live+schedule, flag
  /// `schedule_fallback`). Defaults to [VehicleSource.live] when the backend
  /// doesn't mark it.
  final VehicleSource source;

  /// GTFS trip id for a scheduled object — its identity for de-duplication
  /// against a live vehicle on the same trip. Null for live objects.
  final String? tripId;

  /// Forward timing plan (timed-trajectory feature) and the as-of time it is
  /// anchored to (the source board's last refresh). Both null when the backend
  /// didn't provide a plan (feature off / none available).
  final List<TrajectoryPoint>? trajectory;
  final DateTime? asOf;

  /// route_id of the direction this vehicle is actually travelling (resolved
  /// backend-side). Null on older payloads. Lets the map stitch it to the right
  /// direction's shape instead of the canonical one.
  final String? routeId;

  /// Stable identity for tracking/interpolation across refreshes: garage number
  /// for a live vehicle, GTFS trip id for a scheduled one, else a coordinate
  /// fallback. Prefixed for scheduled so a scheduled and a live object can never
  /// collide on the same key.
  String get key {
    if (garageNo != null) return garageNo!;
    if (source == VehicleSource.scheduled && tripId != null) return 'sched:$tripId';
    return '$line:${lat.toStringAsFixed(5)}:${lon.toStringAsFixed(5)}';
  }

  factory AreaVehicle.fromJson(Map<String, dynamic> json) {
    final asOf = json['as_of'];
    return AreaVehicle(
      line: json['line'] as String,
      vehicleType: VehicleType.fromApi(json['vehicle_type'] as String),
      garageNo: json['garage_no'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      trajectory: TrajectoryPoint.listFromJson(json['trajectory']),
      asOf: asOf is String ? DateTime.tryParse(asOf) : null,
      source: VehicleSource.fromApi(json['source']),
      tripId: json['trip_id'] as String?,
      routeId: json['route_id'] as String?,
    );
  }
}
