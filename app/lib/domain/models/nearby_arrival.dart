import 'arrival.dart' show ServiceStatus;
import 'vehicle_type.dart';

/// One soonest departure inside a [NearbyGroup].
class NearbyEta {
  const NearbyEta({
    required this.etaMinutes,
    required this.garageNo,
    required this.stopsRemaining,
    required this.isScheduled,
  });

  final int etaMinutes;
  final String? garageNo;
  final int? stopsRemaining;

  /// True for a planned (GTFS-schedule) departure with no live vehicle yet —
  /// the "По расписанию" tail that keeps a nearby stop from ever looking empty.
  final bool isScheduled;

  factory NearbyEta.fromJson(Map<String, dynamic> json) {
    return NearbyEta(
      etaMinutes: json['eta_minutes'] as int,
      garageNo: json['garage_no'] as String?,
      stopsRemaining: json['stops_remaining'] as int?,
      isScheduled: json['source'] == 'scheduled',
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
    required this.routeId,
    required this.stopId,
    required this.stopName,
    required this.distanceMeters,
    required this.arrivals,
  });

  final String line;
  final VehicleType vehicleType;

  /// Terminus name = travel direction (resolved backend-side from GTFS line
  /// metadata). Null when the line's metadata carries no destination name.
  final String? destination;

  /// The direction the row groups by: the vehicle's `direction_route_id`, or the
  /// canonical `route_id` as a fallback. Stable id; [destination] is its label.
  final String routeId;

  final String stopId;
  final String stopName;
  final int distanceMeters;

  /// 1–2 soonest departures at [stopId], sorted ascending.
  final List<NearbyEta> arrivals;

  /// Stable identity for list keys / diffing across refreshes.
  String get key => '$line|$routeId|$stopId';

  factory NearbyGroup.fromJson(Map<String, dynamic> json) {
    return NearbyGroup(
      line: json['line'] as String,
      vehicleType: VehicleType.fromApi(json['vehicle_type'] as String),
      destination: json['destination'] as String?,
      routeId: json['route_id'] as String,
      stopId: json['stop_id'] as String,
      stopName: json['stop_name'] as String,
      distanceMeters: (json['distance_meters'] as num).round(),
      arrivals: (json['arrivals'] as List<dynamic>)
          .map((e) => NearbyEta.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// The Nearby list plus the freshness of the boards it came from. `unavailable`
/// means the live feed is down and these groups are schedule-only — the list is
/// still useful, so the UI shows a banner rather than an empty state.
class NearbyResult {
  const NearbyResult({required this.groups, required this.serviceStatus});

  final List<NearbyGroup> groups;
  final ServiceStatus serviceStatus;
}
