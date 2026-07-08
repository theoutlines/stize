import 'vehicle_type.dart';

class LineInfo {
  const LineInfo({
    required this.line,
    required this.vehicleType,
    required this.routeId,
    required this.origin,
    required this.destination,
  });

  final String line;
  final VehicleType vehicleType;
  final String routeId;
  final String origin;
  final String destination;

  factory LineInfo.fromJson(Map<String, dynamic> json) {
    return LineInfo(
      line: json['line'] as String,
      vehicleType: VehicleType.fromApi(json['vehicle_type'] as String),
      routeId: json['route_id'] as String,
      origin: json['origin'] as String,
      destination: json['destination'] as String,
    );
  }
}
