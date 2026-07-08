import 'vehicle_type.dart';

class RouteShapeStop {
  const RouteShapeStop({required this.stopId, required this.name, required this.lat, required this.lon, required this.seq});

  final String stopId;
  final String name;
  final double lat;
  final double lon;
  final int seq;

  factory RouteShapeStop.fromJson(Map<String, dynamic> json) {
    return RouteShapeStop(
      stopId: json['stop_id'] as String,
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      seq: json['seq'] as int,
    );
  }
}

class RouteShape {
  const RouteShape({
    required this.routeId,
    required this.vehicleType,
    required this.origin,
    required this.destination,
    required this.polyline,
    required this.stops,
  });

  final String routeId;
  final VehicleType vehicleType;
  final String origin;
  final String destination;
  final List<List<double>> polyline; // [[lat, lon], ...]
  final List<RouteShapeStop> stops;

  factory RouteShape.fromJson(Map<String, dynamic> json) {
    return RouteShape(
      routeId: json['route_id'] as String,
      vehicleType: VehicleType.fromApi(json['vehicle_type'] as String),
      origin: json['origin'] as String,
      destination: json['destination'] as String,
      polyline: (json['polyline'] as List<dynamic>)
          .map((p) => (p as List<dynamic>).map((v) => (v as num).toDouble()).toList())
          .toList(),
      stops: (json['stops'] as List<dynamic>)
          .map((e) => RouteShapeStop.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
