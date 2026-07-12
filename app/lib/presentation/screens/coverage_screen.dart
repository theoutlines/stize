import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre/maplibre.dart';

import '../../core/coverage_heatmap.dart';
import '../../core/map_style.dart';
import '../../core/map_support.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';

/// Whole-Belgrade overview — independent of the main map's camera (spec).
const _belgradeCenter = Geographic(lon: 20.46, lat: 44.81);
const _overviewZoom = 11.2;

const _layerId = 'coverage-heat';

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
    await style.addSource(coverageSource());
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
    return coverageTabLayer(
      id: _layerId,
      dark: dark,
      filter: _filterExpression(),
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
