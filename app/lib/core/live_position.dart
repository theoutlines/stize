import '../domain/models/arrival.dart';
import '../domain/models/area_vehicle.dart';

/// Whether a garage number is one of the upstream's schedule-derived placeholder
/// ids (`P1..P999`, recycled across vehicles) rather than a real vehicle.
///
/// The source returns these placeholder rows when no live vehicle is assigned
/// yet; their GPS is just the queried stop's own coordinate, so on the map they
/// render as stationary markers stacked on the stop. Mirrors the backend's
/// `vehicleIdOf` (analytics.ts) and the fleet matcher's junk rule so "not a real
/// vehicle" means the same thing everywhere. A `null`/blank or non-`P#####`
/// garage is *not* treated as junk — that's a missing id, not a placeholder, and
/// a real GPS fix should still be trusted.
bool isPlaceholderGarage(String? garageNo) {
  if (garageNo == null) return false;
  final m = RegExp(r'^[Pp](\d+)$').firstMatch(garageNo.trim());
  return m != null && int.parse(m.group(1)!) < 1000;
}

/// Whether an arrival is a genuinely live-tracked vehicle safe to draw as a
/// moving marker on the map: it has a real GPS fix and isn't a placeholder row.
/// Placeholders belong in the arrivals *list* (their ETA is valid) but not on
/// the map.
bool arrivalHasLivePosition(Arrival a) =>
    a.gps != null && !isPlaceholderGarage(a.garageNo);

/// Map-feed counterpart of [arrivalHasLivePosition]: the backend already drops
/// vehicles without GPS from the nearby feed, so here only the placeholder
/// (junk-garage) rows remain to be filtered out.
bool areaVehicleHasLivePosition(AreaVehicle v) =>
    !isPlaceholderGarage(v.garageNo);
