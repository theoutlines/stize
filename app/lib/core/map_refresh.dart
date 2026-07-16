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
