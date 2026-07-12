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

/// The weight (V0 = number of distinct lines along a corridor) is read from a
/// single named property, so a future frequency-/intensity-based weight only
/// needs a new property here + a rebuilt data file — the rest is unchanged.
const _weightProperty = 'routes_count';

/// Weight breakpoints the width/colour ramps are anchored on. Chosen from the
/// built data's distribution (routes_count runs 1…~33).
const _wStops = [1, 3, 6, 12, 20, 33];

/// The three filterable vehicle types, in display order. String values match
/// the `types` array in the coverage GeoJSON.
const _types = <(VehicleType, String)>[
  (VehicleType.tram, 'tram'),
  (VehicleType.trolleybus, 'trolleybus'),
  (VehicleType.bus, 'bus'),
];

/// Coverage map: glowing route corridors over the theme-synced base map. A
/// static, precomputed line layer (from GTFS shapes) styled data-driven by
/// segment weight; a vehicle-type filter and a weight legend sit on top. Not
/// part of the "what's coming to my stop" flow — a standalone infographic tab.
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
      const GeoJsonSource(id: _sourceId, data: '$apiBaseUrl/api/v1/coverage'),
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
        'line-width': _widthExpression(),
        'line-color': _colorExpression(dark),
        'line-opacity': _opacityExpression(),
        // A hair of blur softens the corridors into a subtle glow — still a
        // line-layer property, not a raster blur pass (kept per the spec).
        'line-blur': 0.4,
      },
    );
  }

  // ---- Style expressions ----------------------------------------------------

  /// Only features carrying at least one selected type. Empty selection shows
  /// everything (no filter).
  List<Object>? _filterExpression() {
    if (_selected.isEmpty) return null;
    return [
      'any',
      for (final t in _selected)
        ['in', t, ['get', 'types']],
    ];
  }

  /// Thicker where more lines share the corridor.
  List<Object> _widthExpression() => [
    'interpolate',
    ['linear'],
    ['get', _weightProperty],
    _wStops[0], 0.6,
    _wStops[1], 1.3,
    _wStops[2], 2.3,
    _wStops[3], 3.6,
    _wStops[4], 5.4,
    _wStops[5], 8.0,
  ];

  /// Lower-weight corridors recede a little so the busy ones read as brighter.
  List<Object> _opacityExpression() => [
    'interpolate',
    ['linear'],
    ['get', _weightProperty],
    _wStops[0], 0.55,
    _wStops[2], 0.8,
    _wStops[5], 1.0,
  ];

  /// Colour ramp. With no filter (or several types) it's weight-driven: a warm
  /// ember→white ramp on dark, a light→deep blue ramp on light — high weight
  /// obviously "hotter". With exactly one type selected, the corridor takes that
  /// type's brand colour (from map_support) so the filter reads by hue, and
  /// weight still shows through width + opacity.
  Object _colorExpression(bool dark) {
    if (_selected.length == 1) {
      final type = _types.firstWhere((e) => e.$2 == _selected.first).$1;
      return _hex(vehicleColor(type));
    }
    final ramp = dark ? _warmRamp : _blueRamp;
    return [
      'interpolate',
      ['linear'],
      ['get', _weightProperty],
      for (var i = 0; i < _wStops.length; i++) ...[_wStops[i], ramp[i]],
    ];
  }

  static const _warmRamp = [
    '#7a3d12', // dim ember
    '#c25a1a',
    '#ef7b22', // orange
    '#ffae4d',
    '#ffd9a0',
    '#ffffff', // hottest → white
  ];
  static const _blueRamp = [
    '#9ecae1', // light blue
    '#6baed6',
    '#4292c6',
    '#2171b5',
    '#08519c',
    '#08306b', // deepest navy
  ];

  static String _hex(Color c) =>
      '#${((c.a * 255).round() << 24 | (c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(8, '0').substring(2)}';

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
                  child: _WeightLegend(dark: brightness == Brightness.dark),
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

/// A compact legend for the weight ramp: a thin→thick, dim→bright bar with
/// "fewer … more" captions (Citi Bike-style density key).
class _WeightLegend extends StatelessWidget {
  const _WeightLegend({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final ramp = dark
        ? const [Color(0xFF7A3D12), Color(0xFFEF7B22), Color(0xFFFFD9A0), Color(0xFFFFFFFF)]
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
          // A tapering bar: gradient fill, growing height, to read as
          // "few/thin/dim → many/thick/bright".
          SizedBox(
            width: 168,
            height: 14,
            child: CustomPaint(painter: _LegendBarPainter(ramp)),
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

class _LegendBarPainter extends CustomPainter {
  const _LegendBarPainter(this.ramp);

  final List<Color> ramp;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = LinearGradient(colors: ramp).createShader(rect);
    // A wedge: thin at the left (few lines), full height at the right (many).
    final path = Path()
      ..moveTo(0, size.height * 0.5 - 1)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height * 0.5 + 1)
      ..close();
    canvas.drawPath(path, Paint()..shader = gradient);
  }

  @override
  bool shouldRepaint(_LegendBarPainter oldDelegate) => oldDelegate.ramp != ramp;
}
