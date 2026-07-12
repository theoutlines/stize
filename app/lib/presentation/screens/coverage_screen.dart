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
const _layerId = 'coverage-lines';

/// Warm (dark theme) / blue (light theme) base line colour. Density isn't drawn
/// by a per-feature weight — it emerges from many semi-transparent lines
/// stacking (Strava-heatmap style), so overlapping routes read as brighter.
const _darkColor = '#f0842a'; // warm orange, glows on the dark base
const _lightColor = '#1f66b5'; // readable blue on the light base

/// The three filterable vehicle types, in display order. String values match
/// the `type` property in the coverage GeoJSON.
const _types = <(VehicleType, String)>[
  (VehicleType.tram, 'tram'),
  (VehicleType.trolleybus, 'trolleybus'),
  (VehicleType.bus, 'bus'),
];

/// Coverage map: a Strava-heatmap-style density view. The raw GTFS route shapes
/// are drawn as many semi-transparent lines over the theme-synced base map, so
/// overlapping corridors accumulate brightness — showing where transit is dense
/// and where it thins out, rather than a clean line schematic. Line width + blur
/// interpolate with zoom (far: thick and soft, corridors bleed into glow zones;
/// near: thin and crisp). A vehicle-type filter and a density legend sit on top.
/// Not part of the "what's coming to my stop" flow — a standalone infographic.
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

  /// (Re)creates the source + line layer on a freshly (re)loaded style. Called
  /// on first load and again after every theme flip (setStyle drops layers).
  Future<void> _addCoverageLayer(StyleController style) async {
    await style.addSource(
      // `?rev=` busts any longer-lived CDN/browser cache entry when the data
      // model changes — bump it whenever the coverage.geojson shape changes.
      const GeoJsonSource(id: _sourceId, data: '$apiBaseUrl/api/v1/coverage?rev=2'),
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

  LineStyleLayer _buildLayer() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LineStyleLayer(
      id: _layerId,
      sourceId: _sourceId,
      filter: _filterExpression(),
      layout: const {'line-cap': 'round', 'line-join': 'round'},
      paint: {
        'line-color': _color(dark),
        // Low, zoom-graded opacity is the whole trick: at any one spot a single
        // route is faint, but where many routes overlap the alpha stacks up into
        // a bright corridor. Kept lower at far zoom (more overlap ⇒ avoid
        // blowing the dense core out to mud), higher when zoomed in so lone
        // routes stay visible.
        'line-opacity': [
          'interpolate', ['linear'], ['zoom'],
          11, 0.14,
          14, 0.22,
          16, 0.30,
          18, 0.40,
        ],
        // Far zoom: thick + soft, so corridors bleed together into glow zones.
        // Near zoom: thin + crisp lines.
        'line-width': [
          'interpolate', ['linear'], ['zoom'],
          11, 3.4,
          13, 2.4,
          15, 1.6,
          18, 1.1,
        ],
        'line-blur': [
          'interpolate', ['linear'], ['zoom'],
          11, 3.5,
          13, 2.0,
          15, 0.8,
          18, 0.3,
        ],
      },
    );
  }

  // ---- Style expressions ----------------------------------------------------

  /// Only features whose vehicle type is selected. Empty selection shows all.
  List<Object>? _filterExpression() {
    if (_selected.isEmpty) return null;
    return [
      'any',
      for (final t in _selected)
        ['==', ['get', 'type'], t],
    ];
  }

  /// Base colour: theme-driven warm/blue by default; when exactly one type is
  /// filtered, that type's brand colour (from map_support) so the filter reads
  /// by hue. Density still comes from opacity stacking, not the colour.
  String _color(bool dark) {
    if (_selected.length == 1) {
      final type = _types.firstWhere((e) => e.$2 == _selected.first).$1;
      return _hex(vehicleColor(type));
    }
    return dark ? _darkColor : _lightColor;
  }

  static String _hex(Color c) =>
      '#${((c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(6, '0')}';

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
    final ramp = dark
        ? const [Color(0xFF3A2410), Color(0xFFA85A1E), Color(0xFFF0842A), Color(0xFFFFC98A)]
        : const [Color(0xFFDCE9F5), Color(0xFF6BA3D6), Color(0xFF2E74BE), Color(0xFF0B3D82)];

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
