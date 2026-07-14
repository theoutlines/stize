/// Runtime config fetched from the backend's `/api/v1/config`: the API version
/// plus remotely-togglable feature flags. Flags default to *off* so a missing
/// or unreachable config never accidentally reveals an in-progress feature.
class AppConfig {
  const AppConfig({required this.version, required this.flags});

  final String version;
  final Map<String, bool> flags;

  bool flag(String name) => flags[name] ?? false;

  /// Whether the (draft) transport-analytics screens should be shown to the
  /// user. Gated remotely so screens can ship dormant and be revealed later.
  bool get analyticsShow => flag('analytics_show');

  /// Whether the experimental "Nearby" list (a draggable sheet over the map) is
  /// shown. Off on prod, on on staging — an experiment, not a redesign.
  bool get nearbyList => flag('nearby_list');

  /// Whether the coverage-map tab should be shown to the user. Gated remotely so
  /// the (static infographic) screen can ship dormant and be revealed later.
  bool get coverageMapShow => flag('coverage_map_show');

  /// Whether the main map shows the coverage heatmap as a passive background
  /// when zoomed out (in place of stop clusters). Independent of
  /// [coverageMapShow] — the tab and the overlay gate separately.
  bool get coverageOnMainMap => flag('coverage_on_main_map');

  /// Whether moving vehicles render as a MapLibre GPU symbol layer (batched,
  /// sub-linear in count) instead of per-vehicle Flutter widgets. Client-side
  /// render flag. OFF on prod (the widget path stays the fallback), ON on staging.
  bool get symbolLayer => flag('symbol_layer');

  /// Whether GTFS-schedule-predicted vehicles are shown (semi-transparent) when
  /// there's no live stream — the hybrid live+schedule display. OFF on prod
  /// until confirmed; the backend also gates whether it emits scheduled objects.
  bool get scheduleFallback => flag('schedule_fallback');

  /// Whether the map draws only vehicles with a real live position. The upstream
  /// emits placeholder rows (junk garage `P1..P999`, GPS = the stop coordinate)
  /// that aren't tracked vehicles; when on they stay in the arrivals list but
  /// are not drawn as markers. Gated remotely so it can ship dormant.
  bool get livePositionOnly => flag('live_position_only');

  static const empty = AppConfig(version: '', flags: {});

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final raw = json['flags'];
    final flags = <String, bool>{};
    if (raw is Map) {
      raw.forEach((k, v) => flags[k.toString()] = v == true);
    }
    return AppConfig(version: (json['version'] as String?) ?? '', flags: flags);
  }
}
