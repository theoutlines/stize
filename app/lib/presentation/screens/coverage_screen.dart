import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre/maplibre.dart';

import '../../core/api_config.dart';
import '../../core/map_style.dart';
import '../../core/map_support.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';

/// Whole-Belgrade overview — independent of the main map's camera (spec).
const _belgradeCenter = Geographic(lon: 20.46, lat: 44.81);
const _overviewZoom = 11.2;

const _sourceId = 'coverage-src';
const _layerId = 'coverage-heat';

/// Heatmap colour ramp over `heatmap-density` (0 = transparent). Dark theme:
/// transparent → dark-orange → orange → white-hot (Strava neon on the dark
/// base). Light theme: transparent → blue → deep navy, so density reads on a
/// light base. Density comes from overlapping routes' point clouds, not a
/// per-feature weight.
// Stretched ramp: transparent below ~0.08, then a long dark-orange → orange
// band, with white only in the top ~7% of density — so a single route stays a
// dim dark-orange and only the densest corridors (centre, bridges) burn white.
const _darkRamp = <Object>[
  0.0, 'rgba(0,0,0,0)',
  0.08, 'rgba(60,24,4,0.5)',
  0.4, '#8c370c',
  0.7, '#d65a1a',
  0.85, '#ef7b22',
  0.93, '#ffb860',
  1.0, '#ffffff',
];
const _lightRamp = <Object>[
  0.0, 'rgba(255,255,255,0)',
  0.08, 'rgba(120,170,214,0.45)',
  0.4, '#6baed6',
  0.7, '#3182bd',
  0.85, '#2171b5',
  0.93, '#0b4083',
  1.0, '#08306b',
];

/// The three filterable vehicle types, in display order. String values match
/// the `type` property in the coverage GeoJSON.
const _types = <(VehicleType, String)>[
  (VehicleType.tram, 'tram'),
  (VehicleType.trolleybus, 'trolleybus'),
  (VehicleType.bus, 'bus'),
];

/// Coverage map: a Strava-heatmap-style density view. The GTFS route shapes are
/// resampled to points (server-side) and drawn as a MapLibre heatmap, so
/// overlapping corridors accumulate brightness — showing where transit is dense
/// and where it thins out, rather than a clean line schematic. Radius + intensity
/// interpolate with zoom (far: large radius, corridors bleed into glowing zones
/// ≈ walking reach; near: tighter and crisper). A vehicle-type filter and a
/// density legend sit on top. Not part of the "what's coming to my stop" flow —
/// a standalone infographic.
class CoverageScreen extends ConsumerStatefulWidget {
  const CoverageScreen({super.key, this.onOpenDrawer});

  final VoidCallback? onOpenDrawer;

  @override
  ConsumerState<CoverageScreen> createState() => _CoverageScreenState();
}

class _CoverageScreenState extends ConsumerState<CoverageScreen> {
  MapController? _controller;
  StyleController? _style;
  Brightness? _styleBrightness;

  /// Selected vehicle types (empty = show all). Multi-select.
  final Set<String> _selected = {};

  Future<void> _onStyleLoaded(StyleController style) async {
    _style = style;
    await _addCoverageLayer(style);
  }

  /// (Re)creates the source + heatmap layer on a freshly (re)loaded style.
  /// Called on first load and again after every theme flip (setStyle drops
  /// layers).
  Future<void> _addCoverageLayer(StyleController style) async {
    await style.addSource(
      // `?rev=` busts any longer-lived CDN/browser cache entry when the data
      // model changes — bump it whenever the coverage.geojson shape changes.
      const GeoJsonSource(id: _sourceId, data: '$apiBaseUrl/api/v1/coverage?rev=3'),
    );
    await style.addLayer(_buildLayer());
  }

  /// Reapplies paint + filter after a chip toggle. The 0.3.x StyleController has
  /// no setFilter/setPaint, so swap the layer (the source stays — no refetch).
  Future<void> _refreshLayer() async {
    final style = _style;
    if (style == null) return;
    try {
      await style.removeLayer(_layerId);
    } catch (_) {
      // Layer not present yet (style still loading) — the (re)add covers it.
    }
    await style.addLayer(_buildLayer());
  }

  HeatmapStyleLayer _buildLayer() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return HeatmapStyleLayer(
      id: _layerId,
      sourceId: _sourceId,
      filter: _filterExpression(),
      paint: {
        'heatmap-color': ['interpolate', ['linear'], ['heatmap-density'],
          ...(dark ? _darkRamp : _lightRamp)],
        // Modest radius so corridors don't blob together where routes don't
        // actually cross; a touch larger far out, tighter zoomed in. Tuned
        // against an offline render of the whole-Belgrade view.
        'heatmap-radius': [
          'interpolate', ['linear'], ['zoom'],
          11, 9,
          13, 8,
          15, 7,
          18, 6,
        ],
        // Intensity is low at the overview so only the densest corridors reach
        // white, then rises ~2× per zoom level to counter the point cloud
        // thinning out per pixel as you zoom in (so corridors stay lit and the
        // gradation — dim single lines → orange corridors → white core — holds).
        'heatmap-intensity': [
          'interpolate', ['linear'], ['zoom'],
          11, 0.024,
          13, 0.07,
          15, 0.28,
          18, 1.0,
        ],
        // Slight fade when zoomed right in so the base map shows through.
        'heatmap-opacity': [
          'interpolate', ['linear'], ['zoom'],
          11, 0.9,
          16, 0.85,
          18, 0.65,
        ],
      },
    );
  }

  // ---- Style expressions ----------------------------------------------------

  /// Only points whose vehicle type is selected. Empty selection shows all.
  List<Object>? _filterExpression() {
    if (_selected.isEmpty) return null;
    return [
      'any',
      for (final t in _selected)
        ['==', ['get', 'type'], t],
    ];
  }

  // ---- Filter chips ---------------------------------------------------------

  void _toggle(String? type) {
    setState(() {
      if (type == null) {
        _selected.clear(); // "All"
      } else if (!_selected.remove(type)) {
        _selected.add(type);
      }
    });
    _refreshLayer();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final brightness = theme.brightness;

    // Follow the app theme: swap the base style when brightness flips, then
    // re-add our layer once the new style loads (via _onStyleLoaded).
    if (_styleBrightness == null) {
      _styleBrightness = brightness;
    } else if (_styleBrightness != brightness && _controller != null) {
      _styleBrightness = brightness;
      _style = null;
      // setStyle triggers onStyleLoaded, which re-adds the source + layer.
      _controller!.setStyle(MapStyle.forBrightness(brightness));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navCoverage),
        leading: widget.onOpenDrawer == null
            ? null
            : IconButton(
                icon: const Icon(Icons.menu),
                onPressed: widget.onOpenDrawer,
              ),
      ),
      body: Stack(
        // Expand so the map fills the whole body: without this the Stack sizes
        // to its non-positioned child (the chips/legend column), leaving the
        // map only as wide as the chip row on desktop.
        fit: StackFit.expand,
        children: [
          if (kMapRenderingEnabled)
            Positioned.fill(
              child: MapResizeNudge(
                child: MapLibreMap(
                  options: MapOptions(
                    initCenter: _belgradeCenter,
                    initZoom: _overviewZoom,
                    minZoom: kCityMinZoom,
                    maxZoom: kCityMaxZoom,
                    maxBounds: belgradeMaxBounds,
                    initStyle: MapStyle.forBrightness(brightness),
                  ),
                  onMapCreated: (c) => _controller = c,
                  onStyleLoaded: _onStyleLoaded,
                  children: const [CompactAttribution()],
                ),
              ),
            )
          else
            const Positioned.fill(child: ColoredBox(color: Color(0xFF11151A))),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FilterChips(selected: _selected, onToggle: _toggle),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _DensityLegend(dark: brightness == Brightness.dark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onToggle});

  final Set<String> selected;
  final ValueChanged<String?> onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String label(VehicleType t) => switch (t) {
      VehicleType.tram => l10n.vehicleTypeTram,
      VehicleType.trolleybus => l10n.vehicleTypeTrolleybus,
      VehicleType.bus => l10n.vehicleTypeBus,
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          FilterChip(
            label: Text(l10n.coverageFilterAll),
            selected: selected.isEmpty,
            onSelected: (_) => onToggle(null),
          ),
          for (final (type, value) in _types) ...[
            const SizedBox(width: 8),
            FilterChip(
              avatar: CircleAvatar(
                backgroundColor: vehicleColor(type),
                radius: 6,
              ),
              label: Text(label(type)),
              selected: selected.contains(value),
              onSelected: (_) => onToggle(value),
            ),
          ],
        ],
      ),
    );
  }
}

/// A compact density key: a flat dim→bright gradient bar with "rarer … busier"
/// captions. It mirrors what the map shows — a faint line is one route, a bright
/// corridor is many overlapping — so there are no absolute numbers.
class _DensityLegend extends StatelessWidget {
  const _DensityLegend({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Dim (one faint route) → bright (many stacked), matching the on-map buildup
    // of the base hue over the theme background.
    // Mirror the heatmap-color ramp: dim → hot.
    final ramp = dark
        ? const [Color(0xFF5A2308), Color(0xFFEF7B22), Color(0xFFFFCE8A), Color(0xFFFFFFFF)]
        : const [Color(0xFF9ECAE1), Color(0xFF4292C6), Color(0xFF2171B5), Color(0xFF08306B)];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.coverageLegendTitle,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          // A flat gradient bar: dim → bright, reading as "rare → dense".
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 168,
              height: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: ramp),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 168,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.coverageLegendLow, style: theme.textTheme.labelSmall),
                Text(l10n.coverageLegendHigh, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
