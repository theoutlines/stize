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

/// Whether a single Nearby departure is a genuinely live vehicle (not a
/// schedule prediction, not a `P1..P999` placeholder) — the per-eta counterpart
/// of [nearbyGroupHasLive], so a card can dim/flag each time individually.
bool nearbyEtaIsLive(NearbyEta e) =>
    !e.isScheduled && !isPlaceholderGarage(e.garageNo);

/// The departures a Nearby card should actually show, after the same
/// live/scheduled dedup the arrivals list uses: when the group has live
/// departures, any non-live (scheduled/placeholder) eta at or before the
/// group's latest live eta is dropped — it's the same physical vehicle already
/// represented live, so "6 min / 24 min" can't leave you guessing which is
/// which. A schedule-only group is returned unchanged (never emptied — that's
/// what keeps a nearby stop from looking dead). Order is preserved (ascending).
List<NearbyEta> visibleNearbyEtas(NearbyGroup group) {
  final liveEtas =
      group.arrivals.where(nearbyEtaIsLive).map((e) => e.etaMinutes);
  if (liveEtas.isEmpty) return group.arrivals;
  final horizon = liveEtas.reduce((a, b) => a > b ? a : b);
  final kept = group.arrivals
      .where((e) => nearbyEtaIsLive(e) || e.etaMinutes > horizon)
      .toList();
  // Defensive: never return empty for a group that has live departures.
  return kept.isEmpty
      ? group.arrivals.where(nearbyEtaIsLive).toList()
      : kept;
}

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
