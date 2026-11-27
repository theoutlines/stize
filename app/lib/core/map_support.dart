import 'package:stize/core/design/stize_tokens.dart';
import 'dart:math' as math;
import 'package:stize/core/design/stize_text.dart';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import 'external_link.dart';
import '../domain/models/line_info.dart';
import '../domain/models/stop.dart';
import '../domain/models/vehicle_type.dart';
import '../presentation/widgets/vehicle_icon.dart';
import 'design/stize_icons.dart';

part 'map_images.dart';
part 'vehicle_marker.dart';

/// The camera is fenced to Belgrade and its immediate agglomeration: the app is
/// a *city* transit map, so there's no reason to let the user fly out to a
/// country/continent view (which would also fan the per-stop source out
/// pointlessly wide). Paired with a floor on the zoom in [MapOptions.minZoom].
const belgradeMaxBounds = LngLatBounds(
  longitudeWest: 20.15,
  longitudeEast: 20.80,
  latitudeSouth: 44.63,
  latitudeNorth: 44.98,
);

/// Lowest zoom we allow: keeps the view at city scale, never the whole country.
const kCityMinZoom = 11.0;
const kCityMaxZoom = 18.0;

/// Authoritative line-number → vehicle-type index, sourced from the bundle's
/// lines (their `route_type`, via /api/v1/lines/all). This replaces the old
/// classify-by-number heuristic, which collided suffixed bus lines onto tram
/// numbers ("3A" → "3" → tram) and hardcoded trams 3/7/9 the feed doesn't
/// carry. Set once at startup via [setLineTypeIndex]; used where only a line
/// number is in hand — the tram-rail line set and a stop whose bundle predates
/// per-stop `types`.
class LineTypeIndex {
  const LineTypeIndex(this._byLine);
  const LineTypeIndex._empty() : _byLine = const {};

  /// The empty index: everything resolves to bus until the real one loads.
  static const empty = LineTypeIndex._empty();

  final Map<String, VehicleType> _byLine;

  factory LineTypeIndex.fromLines(Iterable<LineInfo> lines) {
    final byLine = <String, VehicleType>{};
    for (final l in lines) {
      byLine[l.line] = l.vehicleType;
    }
    return LineTypeIndex(byLine);
  }

  /// The type of a line by its number; unknown lines fall back to bus (matching
  /// the backend's default), so an unmapped live-only line never invents a tram.
  VehicleType typeOf(String line) => _byLine[line] ?? VehicleType.bus;

  /// The line numbers the feed types as trams — the tram rail network to draw
  /// (C2). Only lines actually in the bundle, so it can't 404 on absent numbers.
  List<String> get tramLineNumbers => [
    for (final e in _byLine.entries)
      if (e.value == VehicleType.tram) e.key,
  ];
}

LineTypeIndex _lineTypeIndex = LineTypeIndex.empty;

/// Installs the authoritative line→type index (from /api/v1/lines/all). Call
/// once the lines are loaded; safe to call again on refresh.
void setLineTypeIndex(LineTypeIndex index) => _lineTypeIndex = index;

/// The transport type of a line number (bus when the index has not loaded).
VehicleType lineTypeOf(String line) => _lineTypeIndex.typeOf(line);

/// Tram line numbers, exposed so the map can draw the tram rail network (C2).
/// Empty until [setLineTypeIndex] has run.
List<String> get tramLineNumbers => _lineTypeIndex.tramLineNumbers;

/// Thin rail line colour: the tram red, semi-transparent, so the tracks read as
/// tram infrastructure without competing with the markers on top.
const tramRailColor = Color(0x99E4312F);

/// The distinct vehicle types a stop is served by. Prefers the authoritative
/// per-stop `types` emitted by the GTFS build (feed route_type); on a bundle
/// that predates the field (or the offline cache) it resolves each line number
/// through the [LineTypeIndex] instead. Never guesses a type from the number.
Set<VehicleType> stopTypes(Stop stop) {
  if (stop.types.isNotEmpty) return stop.types.toSet();
  return {for (final line in stop.lines) _lineTypeIndex.typeOf(line)};
}

/// The single marker type to draw for a stop, applying type priority.
/// Returns `null` when the stop should use the unified "mixed" marker.
///
/// Trams dominate absolutely: any tram line makes it a tram stop, even when
/// buses (including night buses) or trolleys also call there — a stop on the
/// rails is always a tram stop (owner rule). For non-tram stops the older
/// behaviour stands: more than one type (e.g. bus + trolley) → mixed marker;
/// a single type → that type. Always one marker per stop.
VehicleType? stopMarkerType(Stop stop) {
  final types = stopTypes(stop);
  if (types.contains(VehicleType.tram)) return VehicleType.tram;
  if (types.length > 1) return null; // mixed (e.g. bus + trolley)
  return types.isEmpty ? VehicleType.bus : types.first;
}

/// The marker-image id for a stop, coloured by the type it serves (D1). A stop
/// served by more than one *non-tram* type (e.g. bus + trolley) gets a single
/// *unified* "mixed" marker (D2) rather than several stacked icons — the
/// official app's habit of drawing two pins on a mixed stop is exactly the
/// clutter we avoid. Always one marker per stop.
String stopImageFor(Stop stop) {
  final type = stopMarkerType(stop);
  return type == null ? MapImages.mixedStop : MapImages.forStop(type);
}

/// Works around a MapLibre-on-web init race: the web plugin measures the map
/// container once during `initState` (before Flutter has laid the platform view
/// into its final slot) and only maplibre-gl-js's own ResizeObserver catches
/// *later* size changes — so on first load the map can stay blank (style
/// background painted, but no tiles requested) until something resizes it.
/// This wrapper nudges the child's height by a single pixel one frame after
/// mount, which trips that ResizeObserver and makes the map request its tiles.
/// Harmless (and invisible) on iOS/Android.
class MapResizeNudge extends StatefulWidget {
  const MapResizeNudge({super.key, required this.child});

  final Widget child;

  @override
  State<MapResizeNudge> createState() => _MapResizeNudgeState();
}

class _MapResizeNudgeState extends State<MapResizeNudge> {
  double _pad = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _pad = 0);
      });
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: _pad),
    child: widget.child,
  );
}

/// A small, always-compact map attribution chip for the corner of a map.
///
/// Replaces the maplibre package's `SourceAttribution`, which (a) starts
/// *expanded* — a wide "MapLibre © MapTiler © OpenStreetMap" bar that overlaps
/// markers on first paint — and (b) collapses to a bare circular ⓘ button that
/// reads as a mystery control floating on the map. MapTiler's terms require the
/// attribution to stay visible, so we don't remove it; we just keep it tiny,
/// static, and pinned to a corner (default bottom-left, clear of the bottom
/// search bar). The labels link out to the respective copyright pages.
class CompactAttribution extends StatelessWidget {
  const CompactAttribution({super.key, this.alignment = Alignment.bottomLeft});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = StizeText.of(context).note.copyWith(
      color: scheme.onSurface.withValues(alpha: 0.7),
      fontSize: 10,
      height: 1.0,
    );

    Widget link(String label, String url) => GestureDetector(
      onTap: () => openExternalUrl(url),
      child: Text(label, style: style),
    );

    return SafeArea(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.68),
              borderRadius: BorderRadius.circular(StizeRadius.radiusSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                link('© MapTiler', 'https://www.maptiler.com/copyright/'),
                Text('  ', style: style),
                link(
                  '© OpenStreetMap',
                  'https://www.openstreetmap.org/copyright',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// When false, the MapLibre-backed widgets render a plain placeholder instead
/// of the native map. `MapLibreMap` throws `UnsupportedError` under
/// `flutter test` (no platform implementation), so widget tests that pump a
/// screen containing a map flip this off. Production code never changes it.
bool kMapRenderingEnabled = true;
