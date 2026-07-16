import '../domain/models/arrival.dart';
import '../domain/models/nearby_arrival.dart';
import 'live_position.dart';

/// Which live vehicle a tapped "Nearby" row should follow, or null to open the
/// stop instead (§ owner variant 3). Pure so the row/board status logic is
/// unit-testable.
///
/// - Honours the ROW's own status: a schedule-only group (no live departure)
///   returns null → open the stop, never a phantom vehicle. This uses the group's
///   status, not "any live sibling in the board", so the decision stays
///   consistent with what the row shows even when the Nearby feed and the
///   arrivals board have drifted.
/// - Requires the board to actually carry a live vehicle of the row's
///   line × direction; a drifted status (row says live, board has none) also
///   returns null → open the stop, so we never follow a scheduled/absent vehicle.
/// - Prefers the exact vehicle by garage number (the group's soonest live
///   departure), falling back to the soonest live arrival of the line×direction.
/// Whether a Nearby row leads to a followable live vehicle — the board-less
/// proxy the list uses to decide brightness/clickability (mirrors the arrivals
/// list's [arrivalHasLivePosition] rule). A row is "live" when it has any
/// departure that is neither a schedule prediction nor a placeholder (`P1..P999`)
/// pinned to the stop. Schedule-only / placeholder-only groups read dimmed and
/// their tap opens the stop rather than following a phantom vehicle
/// ([nearbyFollowTarget] returns null for exactly these).
bool nearbyGroupHasLive(NearbyGroup group) => group.arrivals
    .any((e) => !e.isScheduled && !isPlaceholderGarage(e.garageNo));

Arrival? nearbyFollowTarget(NearbyGroup group, List<Arrival> boardArrivals) {
  NearbyEta? liveEta;
  for (final e in group.arrivals) {
    if (!e.isScheduled) {
      liveEta = e;
      break;
    }
  }
  if (liveEta == null) return null; // schedule-only row → open the stop

  Arrival? soonestLive;
  for (final a in boardArrivals) {
    if (a.line != group.line) continue;
    if ((a.directionRouteId ?? a.routeId) != group.routeId) continue;
    if (!arrivalHasLivePosition(a)) continue;
    if (liveEta.garageNo != null && a.garageNo == liveEta.garageNo) {
      return a; // exact vehicle the row is about
    }
    if (soonestLive == null || a.etaMinutes < soonestLive.etaMinutes) {
      soonestLive = a;
    }
  }
  return soonestLive; // null when the board has no live match → open the stop
}
