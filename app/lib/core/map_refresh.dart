/// What the steady 30s refresh tick should do, given the map mode and the active
/// context. Pure so the contract — an active context ALWAYS keeps polling, even
/// during a follow (following is not an input, so it can't stop the data) — is
/// unit-testable without a live map.
enum MapRefresh {
  /// Off-demand: refetch the viewport "aquarium" of vehicles, as before.
  aquarium,

  /// On-demand with a live stop/vehicle context: refetch that stop's arrivals so
  /// its markers (and the followed vehicle) never freeze once the sheet's own
  /// poll dies on close.
  pollStop,

  /// On-demand, no context (state A): nothing to refresh.
  none,
}

MapRefresh mapRefreshAction({
  required bool onDemand,
  required String? stopContextId,
}) {
  if (!onDemand) return MapRefresh.aquarium;
  return stopContextId != null ? MapRefresh.pollStop : MapRefresh.none;
}

/// Whether a freshly-fetched context board is stale enough that we should pull
/// the SWR-revalidated copy a beat later.
///
/// The backend serves `/arrivals` stale-while-revalidate over a 30s cache: a
/// *single* fetch can return an entry older than its TTL (and trigger a
/// background revalidation that only the NEXT fetch sees). A 30s-only client poll
/// therefore oscillates the board's `as_of` between ~fresh and ~60s — and once it
/// crosses the timed-playback staleness gate (45s, see TimedTrajectory) the
/// markers stop predicting and freeze. So after any board older than the SWR TTL
/// we do one quick follow-up fetch to grab the revalidated fresh copy. The
/// threshold sits just above the 30s TTL (a board within TTL is already as fresh
/// as SWR will hand out) and well under the 45s gate.
const int kContextRefetchThresholdSeconds = 32;

bool contextBoardNeedsRefetch(int boardAgeSeconds) =>
    boardAgeSeconds > kContextRefetchThresholdSeconds;
