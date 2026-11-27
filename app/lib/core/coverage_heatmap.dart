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
// Flow lines on the grey data-viz basemap: per vehicle type, routes collapse
// into corridors that carry their weekday trips. Trips set the weight: a lone
// night bus is a hairline in the type's deep tone; a street with hundreds of
// trams a day is a thick stroke that runs to the type's light tint and glows.

/// Coverage mode takes in the whole city.
const coverageOverviewCenter = Geographic(lon: 20.46, lat: 44.80);
const coverageOverviewZoom = 11.4;

/// Corridors with `type` and `trips` (backend `build-coverage-flow.mjs`).
const coverageFlowSourceId = 'coverage-flow-src';
const coverageFlowUrl = '$apiBaseUrl/api/v1/coverage/flow?rev=4';

GeoJsonSource coverageFlowSource() =>
    GeoJsonSource(id: coverageFlowSourceId, data: coverageFlowUrl);

/// The coverage `type` values, bottom layer first: bus (the widest network)
/// lowest, tram on top.
const coverageTypes = <String>['bus', 'trolleybus', 'tram'];

/// Per type: deep tone, transit colour, bright tint, peak tint. The middle
/// stop is the type's transit colour; the tints keep the three hues glowing
/// together (blue to cyan, orange to yellow, red to coral) instead of muddying
/// where they cross. Tuned on staging, 2026-11-27.
const _coverageRamps = <String, List<String>>{
  'bus': ['#123FA8', '#2278E6', '#38B6FF', '#B8F2FF'],
  'trolleybus': ['#8A3D00', '#EA7000', '#FFB020', '#FFF0B0'],
  'tram': ['#8A1018', '#E4312F', '#FF6A4D', '#FFD6C8'],
};

/// Trips/day where each type reaches its ramp stops. Bus corridors run far
/// busier (up to ~4000 a day on the bridges) than tram or trolleybus (~1400).
const _coverageTripStops = <String, List<num>>{
  'bus': [20, 300, 1200, 3000],
  'trolleybus': [50, 250, 700, 1100],
  'tram': [50, 250, 700, 1300],
};

String coverageFlowLayerId(String type) => 'coverage-flow-$type';
String coverageGlowLayerId(String type) => 'coverage-glow-$type';

List<Object> _isType(String type) => [
  '==',
  ['get', 'type'],
  type,
];

/// Line width by trips at the city view, times [k]: a hairline for a few
/// trips, ~6.5 px for the busiest corridor.
List<Object> _widthByTrips(double k) => [
  'interpolate',
  ['linear'],
  ['get', 'trips'],
  1,
  0.4 * k,
  50,
  0.9 * k,
  300,
  2 * k,
  1000,
  3.6 * k,
  4000,
  6.5 * k,
];

/// The width over zoom: as above at the city view, 1.6× up close.
List<Object> _width(double k) => [
  'interpolate',
  ['linear'],
  ['zoom'],
  11,
  _widthByTrips(k),
  15,
  _widthByTrips(k * 1.6),
];

/// Colour by trips along the type's ramp.
List<Object> _colorByTrips(String type) {
  final r = _coverageRamps[type]!;
  final t = _coverageTripStops[type]!;
  return [
    'interpolate',
    ['linear'],
    ['get', 'trips'],
    t[0], r[0], t[1], r[1], t[2], r[2], t[3], r[3], //
  ];
}

/// The crisp stroke of one [type]'s corridors.
LineStyleLayer coverageFlowLayer({required String type}) => LineStyleLayer(
  id: coverageFlowLayerId(type),
  sourceId: coverageFlowSourceId,
  filter: _isType(type),
  layout: const {'line-cap': 'round', 'line-join': 'round'},
  paint: {
    'line-color': _colorByTrips(type),
    'line-width': _width(1),
    'line-opacity': 0.9,
  },
);

/// The glow under one [type]'s corridors: wide and soft, so busy streets
/// shine and the city view melts into corridors.
LineStyleLayer coverageGlowLayer({required String type, required bool dark}) =>
    LineStyleLayer(
      id: coverageGlowLayerId(type),
      sourceId: coverageFlowSourceId,
      filter: _isType(type),
      layout: const {'line-cap': 'round', 'line-join': 'round'},
      paint: {
        'line-color': _colorByTrips(type),
        'line-width': _width(4),
        'line-blur': _width(3),
        'line-opacity': dark ? 0.22 : 0.16,
      },
    );
