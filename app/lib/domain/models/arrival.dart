import 'vehicle_type.dart';

class LatLon {
  const LatLon(this.lat, this.lon);

  final double lat;
  final double lon;

  factory LatLon.fromJson(Map<String, dynamic> json) {
    return LatLon((json['lat'] as num).toDouble(), (json['lon'] as num).toDouble());
  }
}

class Arrival {
  const Arrival({
    required this.line,
    required this.vehicleType,
    required this.etaMinutes,
    required this.stopsRemaining,
    required this.routeId,
    required this.gps,
    required this.garageNo,
    this.heading,
  });

  final String line;
  final VehicleType vehicleType;
  final int etaMinutes;
  final int? stopsRemaining;
  final String routeId;
  final LatLon? gps;
  final String? garageNo;

  /// Travel direction in degrees (0 = north, clockwise), or null if unknown.
  final double? heading;

  factory Arrival.fromJson(Map<String, dynamic> json) {
    return Arrival(
      line: json['line'] as String,
      vehicleType: VehicleType.fromApi(json['vehicle_type'] as String),
      etaMinutes: json['eta_minutes'] as int,
      stopsRemaining: json['stops_remaining'] as int?,
      routeId: json['route_id'] as String,
      gps: json['gps'] == null ? null : LatLon.fromJson(json['gps'] as Map<String, dynamic>),
      garageNo: json['garage_no'] as String?,
      heading: (json['heading'] as num?)?.toDouble(),
    );
  }
}

enum ServiceStatus {
  ok,
  unavailable;

  static ServiceStatus fromApi(String value) {
    return value == 'ok' ? ServiceStatus.ok : ServiceStatus.unavailable;
  }
}

class ArrivalsBoard {
  const ArrivalsBoard({
    required this.stopId,
    required this.stopName,
    required this.updatedAt,
    required this.arrivals,
    required this.serviceStatus,
  });

  final String stopId;
  final String stopName;
  final DateTime updatedAt;
  final List<Arrival> arrivals;
  final ServiceStatus serviceStatus;

  factory ArrivalsBoard.fromJson(Map<String, dynamic> json) {
    return ArrivalsBoard(
      stopId: json['stop_id'] as String,
      stopName: json['stop_name'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      arrivals: (json['arrivals'] as List<dynamic>)
          .map((e) => Arrival.fromJson(e as Map<String, dynamic>))
          .toList(),
      serviceStatus: ServiceStatus.fromApi(json['service_status'] as String),
    );
  }
}
