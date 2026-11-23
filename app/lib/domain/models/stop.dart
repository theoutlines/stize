import 'vehicle_type.dart';

class Stop {
  const Stop({
    required this.stopId,
    required this.name,
    required this.lat,
    required this.lon,
    required this.lines,
    this.types = const [],
  });

  final String stopId;
  final String name;
  final double lat;
  final double lon;
  final List<String> lines;

  /// The distinct vehicle types serving this stop, from the feed's authoritative
  /// route_type (emitted by the GTFS build). The marker type is derived from
  /// this, not guessed from line numbers. Empty on a bundle that predates the
  /// field (or the offline cache) — callers fall back to the line→type index.
  final List<VehicleType> types;

  factory Stop.fromJson(Map<String, dynamic> json) {
    return Stop(
      stopId: json['stop_id'] as String,
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      lines: (json['lines'] as List<dynamic>).cast<String>(),
      types:
          (json['types'] as List<dynamic>?)
              ?.map((e) => VehicleType.fromApi(e as String))
              .toList() ??
          const [],
    );
  }
}
