
import '../../core/fleet_matcher.dart';

/// Vehicle age in whole years from the middle of the build range, or null when
/// build years are unknown. Anchored to the current calendar year.
int? fleetAgeYears(FleetVehicle fleet, {DateTime? now}) {
  final mid = fleet.midYear;
  if (mid == null) return null;
  final year = (now ?? DateTime.now()).year;
  final age = year - mid;
  return age < 0 ? 0 : age;
}
