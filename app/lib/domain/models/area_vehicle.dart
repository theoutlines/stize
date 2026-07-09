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
  });

  final String line;
  final VehicleType vehicleType;
  final String? garageNo;
  final double lat;
  final double lon;
  final double? heading;

  /// Stable identity for tracking/interpolation across refreshes.
  String get key =>
      garageNo ?? '$line:${lat.toStringAsFixed(5)}:${lon.toStringAsFixed(5)}';

  factory AreaVehicle.fromJson(Map<String, dynamic> json) {
    return AreaVehicle(
      line: json['line'] as String,
      vehicleType: VehicleType.fromApi(json['vehicle_type'] as String),
      garageNo: json['garage_no'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
    );
  }
}
