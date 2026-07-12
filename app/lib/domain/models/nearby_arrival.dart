import 'vehicle_type.dart';

/// One soonest departure inside a [NearbyGroup].
class NearbyEta {
  const NearbyEta({
    required this.etaMinutes,
    required this.garageNo,
    required this.stopsRemaining,
  });

  final int etaMinutes;
  final String? garageNo;
  final int? stopsRemaining;

  factory NearbyEta.fromJson(Map<String, dynamic> json) {
    return NearbyEta(
      etaMinutes: json['eta_minutes'] as int,
      garageNo: json['garage_no'] as String?,
      stopsRemaining: json['stops_remaining'] as int?,
    );
  }
}

/// One row of the "Nearby" list: a single line in one direction, anchored to the
/// nearest stop that serves it, with its soonest departures. Built entirely
/// backend-side (see backend `getNearbyArrivals`) — the client only renders it.
class NearbyGroup {
  const NearbyGroup({
    required this.line,
    required this.vehicleType,
    required this.destination,
    required this.directionId,
    required this.stopId,
    required this.stopName,
    required this.distanceMeters,
    required this.arrivals,
  });

  final String line;
  final VehicleType vehicleType;

  /// Terminus name = travel direction. Null when the upstream carried no route
  /// geometry to derive it from.
  final String? destination;
  final String? directionId;

  final String stopId;
  final String stopName;
  final int distanceMeters;

  /// 1–2 soonest departures at [stopId], sorted ascending.
  final List<NearbyEta> arrivals;

  /// Stable identity for list keys / diffing across refreshes.
  String get key => '$line|${destination ?? directionId ?? ''}|$stopId';

  factory NearbyGroup.fromJson(Map<String, dynamic> json) {
    return NearbyGroup(
      line: json['line'] as String,
      vehicleType: VehicleType.fromApi(json['vehicle_type'] as String),
      destination: json['destination'] as String?,
      directionId: json['direction_id'] as String?,
      stopId: json['stop_id'] as String,
      stopName: json['stop_name'] as String,
      distanceMeters: (json['distance_meters'] as num).round(),
      arrivals: (json['arrivals'] as List<dynamic>)
          .map((e) => NearbyEta.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
