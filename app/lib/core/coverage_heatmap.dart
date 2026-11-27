// Shared coverage-heatmap source and style for the home map: the zoomed-out
// backdrop and coverage mode (the menu's Coverage level).
//
// Both draw from the one source here; each tunes its own look.

import 'package:maplibre/maplibre.dart';

import 'api_config.dart';

/// GeoJSON source id, shared by the backdrop and coverage mode in the one
/// style (added once, fetched once).
const coverageSourceId = 'coverage-src';

/// `?rev=` busts any longer-lived CDN/browser cache entry when the data model
/// changes — bump it whenever the coverage.geojson shape changes.
const coverageDataUrl = '$apiBaseUrl/api/v1/coverage?rev=3';

/// Heatmap colour ramp over `heatmap-density` (0 = transparent). Dark theme:
/// transparent → dark-orange → orange → white-hot (Strava neon on the dark
/// base). Light theme: transparent → blue → deep navy, so density reads on a
/// light base. Density comes from overlapping routes' point clouds, not a
/// per-feature weight.
// Stretched ramp: transparent below ~0.08, then a long dark-orange → orange
// band, with white only in the top ~7% of density — so a single route stays a
// dim dark-orange and only the densest corridors (centre, bridges) burn white.
const coverageDarkRamp = <Object>[
  0.0,
  'rgba(0,0,0,0)',
  0.08,
  'rgba(60,24,4,0.5)',
  0.4,
  '#8c370c',
  0.7,
  '#d65a1a',
  0.85,
  '#ef7b22',
  0.93,
  '#ffb860',
  1.0,
  '#ffffff',
];
const coverageLightRamp = <Object>[
  0.0,
  'rgba(255,255,255,0)',
  0.08,
  'rgba(120,170,214,0.45)',
  0.4,
  '#6baed6',
  0.7,
  '#3182bd',
  0.85,
  '#2171b5',
  0.93,
  '#0b4083',
  1.0,
  '#08306b',
];

/// The shared GeoJSON source. Adding this to a style triggers the data fetch;
/// callers control *when* (the main map adds it lazily on first zoom-out).
GeoJsonSource coverageSource() =>
    const GeoJsonSource(id: coverageSourceId, data: coverageDataUrl);

/// `heatmap-color` expression for the current theme (shared by both surfaces).
List<Object> coverageColorExpression(bool dark) => [
  'interpolate',
  ['linear'],
  ['heatmap-density'],
  ...(dark ? coverageDarkRamp : coverageLightRamp),
];

/// `heatmap-radius` ramp over zoom. Modest so corridors don't blob together
/// where routes don't actually cross; a touch larger far out, tighter zoomed
/// in. Identical on both surfaces (radius is about spatial spread, not
/// emphasis).
List<Object> coverageRadiusExpression() => [
  'interpolate',
  ['linear'],
  ['zoom'],
  11,
  9,
  13,
  8,
  15,
  7,
  18,
  6,
];

// ---- Main-map overlay (passive background at zoom-out) ---------------------
//
// On the main map the heatmap is a *background* that replaces the numbered
// stop clusters when zoomed out, then fades away as the user zooms in and the
// stops take over. So it runs at a lower intensity/opacity than the tab (reads
// as ambient glow, not the main content) and crossfades with the stops over a
// zoom band.

/// Layer id for the main-map overlay (distinct from the tab's, though they're
/// in separate styles anyway).
const coverageMainLayerId = 'coverage-heat-main';

/// At/below this zoom the overlay is fully (modestly) visible and the stops are
/// hidden; the heatmap stands in for the clusters. Tuned near the zoom where
/// stops currently collapse into clusters (~15) so the swap reads naturally.
const kCoverageMainFadeStart = 14.0;

/// At/above this zoom the overlay is gone and stops/clusters are fully shown.
const kCoverageMainFadeEnd = 14.8;

/// Modest peak opacity so the overlay reads as a background layer, not the main
/// content (the Coverage tab runs much hotter).
const kCoverageMainMaxOpacity = 0.55;

/// Extra sticky band, above [kCoverageMainFadeEnd], for the discrete "is the
/// layer mounted" decision — so a zoom hovering at the threshold doesn't
/// repeatedly mount/unmount (or re-fetch) the layer.
const kCoverageMainHysteresis = 0.5;

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// 0 at [kCoverageMainFadeStart] → 1 at [kCoverageMainFadeEnd]; the crossfade
/// progress used to swap heatmap ⇄ stops.
double _fadeProgress(double zoom) =>
    ((zoom - kCoverageMainFadeStart) /
            (kCoverageMainFadeEnd - kCoverageMainFadeStart))
        .clamp(0.0, 1.0);

/// Main-map heatmap opacity at [zoom]: modest peak far out → 0 as stops take
/// over. Mirrors [coverageMainOpacityExpression] (both derive from the same
/// fade constants, so they cannot diverge).
double coverageMainHeatmapOpacity(double zoom) =>
    _lerp(kCoverageMainMaxOpacity, 0.0, _fadeProgress(zoom));

/// Main-map stop/cluster marker opacity at [zoom]: hidden under the heatmap far
/// out, full once zoomed in past the band (the inverse crossfade).
double coverageMainStopsOpacity(double zoom) => _fadeProgress(zoom);

/// Whether the heatmap layer should be mounted at [zoom], given whether it was
/// mounted a moment ago ([wasActive]). Hysteresis: once mounted it stays until
/// the user zooms in past [kCoverageMainFadeEnd] + [kCoverageMainHysteresis];
/// once unmounted it re-mounts only below [kCoverageMainFadeEnd]. This is the
/// pure threshold logic the unit tests pin down.
bool coverageMainHeatmapActive({
  required double zoom,
  required bool wasActive,
}) {
  if (wasActive) return zoom < kCoverageMainFadeEnd + kCoverageMainHysteresis;
  return zoom < kCoverageMainFadeEnd;
}

/// `heatmap-opacity` expression for the overlay: a GPU-side zoom crossfade so
/// the fade is smooth *during* a pinch (no Flutter rebuild). Built from the
/// same constants as [coverageMainHeatmapOpacity].
List<Object> coverageMainOpacityExpression() => [
  'interpolate',
  ['linear'],
  ['zoom'],
  kCoverageMainFadeStart,
  kCoverageMainMaxOpacity,
  kCoverageMainFadeEnd,
  0.0,
];

/// `heatmap-intensity` for the overlay — deliberately lower than the tab so the
/// layer stays a soft background, but high enough to read as an ambient glow.
/// Only spans the zoom band where it's visible (≤ [kCoverageMainFadeEnd]); rises
/// with zoom to counter the point cloud thinning per pixel as you zoom in.
/// Tuned live against the whole-Belgrade overview on staging.
List<Object> coverageMainIntensityExpression() => [
  'interpolate',
  ['linear'],
  ['zoom'],
  11,
  0.04,
  12.5,
  0.07,
  14,
  0.14,
  14.8,
  0.22,
];

/// The heatmap layer for the main-map overlay.
HeatmapStyleLayer coverageMainLayer({required bool dark}) => HeatmapStyleLayer(
  id: coverageMainLayerId,
  sourceId: coverageSourceId,
  paint: {
    'heatmap-color': coverageColorExpression(dark),
    'heatmap-radius': coverageRadiusExpression(),
    'heatmap-intensity': coverageMainIntensityExpression(),
    'heatmap-opacity': coverageMainOpacityExpression(),
  },
);

// ---- Coverage mode (the menu's Coverage, over the home map) ---------------
//
// One heat layer per vehicle type, each in that type's transit colour, so the
// map shows not just where transit is dense but what runs there. Where two
// types share a corridor their glows overlap and the colours mix. Bus (the
// widest network) sits lowest and tram (the fewest lines) on top, each a little
// see-through so the one underneath still tints the overlap.

/// Coverage mode takes in the whole city.
const coverageOverviewCenter = Geographic(lon: 20.46, lat: 44.80);
const coverageOverviewZoom = 11.4;

/// The coverage `type` values, bottom layer first.
const coverageTypes = <String>['bus', 'trolleybus', 'tram'];

/// Layer id of one type's heat in coverage mode.
String coverageModeLayerId(String type) => 'coverage-mode-$type';

String _rgba(int argb, double alpha) {
  final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
  return 'rgba($r,$g,$b,${alpha.toStringAsFixed(2)})';
}

/// [argb] mixed toward white (t > 0) or black (t < 0) by |t|.
int _shade(int argb, double t) {
  int ch(int v) => t >= 0
      ? (v + (255 - v) * t).round()
      : (v * (1 + t)).round();
  final r = ch((argb >> 16) & 0xFF),
      g = ch((argb >> 8) & 0xFF),
      b = ch(argb & 0xFF);
  return 0xFF000000 | (r << 16) | (g << 8) | b;
}

/// Heat ramp for one type. A lone route is a thin veil of the type's colour;
/// a corridor reaches the full colour; only the densest cores go past it:
/// lighter on the dark map (glow), deeper on the light map (ink), so the heat
/// never sinks into the base map's own tones.
List<Object> coverageTypeColorExpression(int argb, {required bool dark}) => [
  'interpolate',
  ['linear'],
  ['heatmap-density'],
  0.0,
  _rgba(argb, 0),
  0.06,
  _rgba(argb, dark ? 0.22 : 0.18),
  0.35,
  _rgba(argb, dark ? 0.6 : 0.55),
  0.7,
  _rgba(argb, 0.95),
  0.9,
  _rgba(_shade(argb, dark ? 0.35 : -0.1), 1),
  1.0,
  _rgba(_shade(argb, dark ? 0.7 : -0.25), 1),
];

/// Intensity per type at the city overview. Bus covers the most ground, so
/// it runs cooler; tram and trolleybus, with few lines each, run hotter so a
/// single line still reaches its full colour. Tuned live on staging
/// (2026-11-27).
const _coverageModeBaseIntensity = {
  'bus': 0.05,
  'trolleybus': 0.12,
  'tram': 0.12,
};

/// Intensity over zoom for one type: rises as the points thin out per pixel.
List<Object> coverageModeIntensityExpression(String type) {
  final i = _coverageModeBaseIntensity[type] ?? 0.08;
  return [
    'interpolate',
    ['linear'],
    ['zoom'],
    11,
    i,
    13,
    i * 2.6,
    15,
    i * 9,
    18,
    i * 30,
  ];
}

/// Narrow strands, so each route reads as a line (the refs: fine traces that
/// add up to bright corridors) rather than a cloud.
List<Object> coverageModeRadiusExpression() => [
  'interpolate',
  ['linear'],
  ['zoom'],
  11,
  6,
  15,
  7,
];

/// Layer id of the veil that mutes the base map under the heat.
const coverageModeVeilId = 'coverage-mode-veil';

/// A veil in the page colour over the base map, under the heat, so the
/// transit colours never sink into the map's own blues and greens.
BackgroundStyleLayer coverageModeVeil({
  required int bgArgb,
  required bool dark,
}) => BackgroundStyleLayer(
  id: coverageModeVeilId,
  paint: {'background-color': _rgba(bgArgb, dark ? 0.55 : 0.7)},
);

/// The heat layer for one [type] in coverage mode.
HeatmapStyleLayer coverageModeLayer({
  required String type,
  required int argb,
  required bool dark,
}) => HeatmapStyleLayer(
  id: coverageModeLayerId(type),
  sourceId: coverageSourceId,
  filter: [
    '==',
    ['get', 'type'],
    type,
  ],
  paint: {
    'heatmap-color': coverageTypeColorExpression(argb, dark: dark),
    'heatmap-radius': coverageModeRadiusExpression(),
    'heatmap-intensity': coverageModeIntensityExpression(type),
    'heatmap-opacity': 0.85,
  },
);
