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

  /// Whether the coverage-map tab should be shown to the user. Gated remotely so
  /// the (static infographic) screen can ship dormant and be revealed later.
  bool get coverageMapShow => flag('coverage_map_show');

  /// Whether the main map shows the coverage heatmap as a passive background
  /// when zoomed out (in place of stop clusters). Independent of
  /// [coverageMapShow] — the tab and the overlay gate separately.
  bool get coverageOnMainMap => flag('coverage_on_main_map');

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
