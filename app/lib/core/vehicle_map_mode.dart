/// How the main map renders vehicles.
enum VehicleMapMode {
  /// No background fetch: vehicles appear only in context (a tapped stop's
  /// arrivals, a followed vehicle). The default once the feature is enabled.
  onDemand,

  /// The background "aquarium": every vehicle in the viewport, refetched on the
  /// steady cadence. The historical behaviour, now an opt-in.
  aquarium,
}

/// Resolves the map mode from the remote `vehicles_on_demand` flag and the
/// user's stored choice. Two levels, in this order:
///
/// - flag OFF is a **killswitch**: the setting isn't offered at all and the map
///   is the aquarium, exactly as production behaves today — one KV write reverts
///   the whole feature, whatever any user has stored;
/// - flag ON: the setting is offered, on-demand is the default, and an explicit
///   user choice wins over that default.
///
/// [choice] is null until the user picks a value (they never have, or they're on
/// a fresh install) — that's what makes the default apply.
VehicleMapMode resolveVehicleMapMode({
  required bool flagOn,
  required VehicleMapMode? choice,
}) {
  if (!flagOn) return VehicleMapMode.aquarium;
  return choice ?? VehicleMapMode.onDemand;
}
