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

/// Whether an in-flight background "aquarium" vehicle fetch's result should still
/// be applied when it lands.
///
/// A fetch kicked off while off-demand (e.g. in the window after a reload, before
/// `/config` resolves the flag to ON) must be DISCARDED once we're on-demand —
/// otherwise the whole background set (buses, trams, scheduled objects) leaks
/// onto a context-less on-demand map. Also drops results for an unmounted screen
/// or a superseded request.
bool keepAquariumResult({
  required bool mounted,
  required bool current,
  required bool onDemand,
}) =>
    mounted && current && !onDemand;
