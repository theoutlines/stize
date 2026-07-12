// Shared coverage-heatmap source and style, used by BOTH the Coverage tab
// (`presentation/screens/coverage_screen.dart`) and the main map's zoomed-out
// overlay (`presentation/screens/home_map_screen.dart`).
//
// The two surfaces must render the *same* layer from the *same* data — a
// divergence in source id, colour ramp or radius/intensity expressions between
// the two would be a bug by definition (spec). So all of that lives here only;
// each screen just tunes its own intensity/opacity for its context.

import 'package:maplibre/maplibre.dart';

import 'api_config.dart';

/// GeoJSON source id. Both maps use the same id (they live in separate
/// `StyleController`s, so there is no collision) fed by the same URL, so the
/// HTTP/browser cache dedupes the actual download — there is no second network
/// fetch even though each style needs its own source object.
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
  0.0, 'rgba(0,0,0,0)',
  0.08, 'rgba(60,24,4,0.5)',
  0.4, '#8c370c',
  0.7, '#d65a1a',
  0.85, '#ef7b22',
  0.93, '#ffb860',
  1.0, '#ffffff',
];
const coverageLightRamp = <Object>[
  0.0, 'rgba(255,255,255,0)',
  0.08, 'rgba(120,170,214,0.45)',
  0.4, '#6baed6',
  0.7, '#3182bd',
  0.85, '#2171b5',
  0.93, '#0b4083',
  1.0, '#08306b',
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
  11, 9,
  13, 8,
  15, 7,
  18, 6,
];

// ---- Coverage tab (foreground infographic) --------------------------------

/// `heatmap-intensity` for the standalone Coverage tab. Low at the overview so
/// only the densest corridors reach white, then rising ~2× per zoom level to
/// counter the point cloud thinning out per pixel as you zoom in (so corridors
/// stay lit and the gradation — dim single lines → orange corridors → white
/// core — holds).
List<Object> coverageTabIntensityExpression() => [
  'interpolate',
  ['linear'],
  ['zoom'],
  11, 0.024,
  13, 0.07,
  15, 0.28,
  18, 1.0,
];

/// `heatmap-opacity` for the Coverage tab — mostly opaque, a slight fade when
/// zoomed right in so the base map shows through.
List<Object> coverageTabOpacityExpression() => [
  'interpolate',
  ['linear'],
  ['zoom'],
  11, 0.9,
  16, 0.85,
  18, 0.65,
];

/// The heatmap layer for the Coverage tab. [filter] narrows the vehicle types.
HeatmapStyleLayer coverageTabLayer({
  required String id,
  required bool dark,
  List<Object>? filter,
}) => HeatmapStyleLayer(
  id: id,
  sourceId: coverageSourceId,
  filter: filter,
  paint: {
    'heatmap-color': coverageColorExpression(dark),
    'heatmap-radius': coverageRadiusExpression(),
    'heatmap-intensity': coverageTabIntensityExpression(),
    'heatmap-opacity': coverageTabOpacityExpression(),
  },
);

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
  kCoverageMainFadeStart, kCoverageMainMaxOpacity,
  kCoverageMainFadeEnd, 0.0,
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
  11, 0.04,
  12.5, 0.07,
  14, 0.14,
  14.8, 0.22,
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
