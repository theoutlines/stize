import 'vehicle_type.dart';

class LineInfo {
  const LineInfo({
    required this.line,
    required this.vehicleType,
    required this.routeId,
    required this.origin,
    required this.destination,
    this.directionId,
  });

  final String line;
  final VehicleType vehicleType;

  /// Per-direction shape key. The canonical direction keeps the bare GTFS
  /// route_id; the other direction is "{route_id}-{direction_id}" (F8). Fetch a
  /// direction's shape by this id, not by line number (which is canonical-only).
  final String routeId;
  final String origin;
  final String destination;

  /// GTFS direction ("0"/"1"), when known: a line appears once per direction in
  /// search results, distinguished by its origin → destination.
  final String? directionId;

  factory LineInfo.fromJson(Map<String, dynamic> json) {
    return LineInfo(
      line: json['line'] as String,
      vehicleType: VehicleType.fromApi(json['vehicle_type'] as String),
      routeId: json['route_id'] as String,
      origin: json['origin'] as String,
      destination: json['destination'] as String,
      directionId: json['direction_id'] as String?,
    );
  }
}
