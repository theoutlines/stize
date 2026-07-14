import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/models/stop.dart';
import '../domain/models/vehicle_type.dart';
import '../presentation/widgets/vehicle_icon.dart';

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

// Belgrade line-number → vehicle-type heuristic. The stops feed only carries
// line numbers (not a per-stop vehicle type), so classify by the well-known
// GSP tram and trolleybus line sets; everything else is a bus. Good enough to
// pick a stop's marker icon.
const _tramLines = {'2', '3', '5', '6', '7', '9', '10', '11', '12', '13', '14'};
const _trolleyLines = {'19', '21', '22', '28', '29', '40', '41'};

/// Tram line numbers, exposed so the map can draw the tram rail network (C2).
List<String> get tramLineNumbers => _tramLines.toList();

/// Thin rail line colour: the tram red, semi-transparent, so the tracks read as
/// tram infrastructure without competing with the markers on top.
const tramRailColor = Color(0x99D3342B);

VehicleType classifyLine(String line) {
  final numeric = RegExp(r'^\d+').firstMatch(line)?.group(0) ?? line;
  if (_tramLines.contains(numeric)) return VehicleType.tram;
  if (_trolleyLines.contains(numeric)) return VehicleType.trolleybus;
  return VehicleType.bus;
}

/// A stop's marker type: trams are the most distinctive, so a stop served by
/// any tram line reads as a tram stop, then trolley, otherwise bus.
VehicleType stopPrimaryType(Stop stop) {
  var hasTrolley = false;
  for (final line in stop.lines) {
    final type = classifyLine(line);
    if (type == VehicleType.tram) return VehicleType.tram;
    if (type == VehicleType.trolleybus) hasTrolley = true;
  }
  return hasTrolley ? VehicleType.trolleybus : VehicleType.bus;
}

/// The distinct vehicle types a stop is served by (from its line numbers).
Set<VehicleType> stopTypes(Stop stop) {
  final types = <VehicleType>{};
  for (final line in stop.lines) {
    types.add(classifyLine(line));
  }
  return types;
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
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurface.withValues(alpha: 0.7),
      fontSize: 9.5,
      height: 1.0,
    );

    Widget link(String label, String url) => GestureDetector(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Text(label, style: style),
    );

    return SafeArea(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.68),
              borderRadius: BorderRadius.circular(6),
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

/// Registered image ids used by the MapLibre symbol/marker layers.
class MapImages {
  const MapImages._();

  static const bus = 'stg-bus';
  static const tram = 'stg-tram';
  static const trolley = 'stg-trolley';
  static const mixedStop = 'stg-stop-mixed';
  static const favorite = 'stg-fav';
  static const place = 'stg-place';
  static const vehicle = 'stg-vehicle';
  static const me = 'stg-me';
  static const cluster = 'stg-cluster';

  static String forStop(VehicleType type) => switch (type) {
    VehicleType.bus => bus,
    VehicleType.tram => tram,
    VehicleType.trolleybus => trolley,
  };
}

/// A stop pin, styled to stand out from the base map so it's clearly the
/// tappable thing on screen: a **white** disc (lifts off both the light and the
/// dark map style — a theme-`surface` disc blended into its matching map) with
/// a bold coloured ring, the transport-type glyph, and a soft drop shadow.
/// Deliberately hollow (white-filled), keeping it distinct from the solid
/// moving-vehicle markers.
Widget _stopPin(Widget glyph, Color color, ColorScheme scheme) {
  return SizedBox(
    width: 48,
    height: 48,
    child: Center(
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 3.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 5,
              spreadRadius: 0.5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: glyph,
      ),
    ),
  );
}

/// A filled marker for a moving vehicle — solid colour so it reads as "live",
/// distinct from the hollow stop pins.
Widget _vehiclePin(IconData icon, Color color, ColorScheme scheme) {
  return SizedBox(
    width: 36,
    height: 36,
    child: Center(
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.surface, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Icon(icon, color: scheme.onPrimary, size: 17),
      ),
    ),
  );
}

/// The user's own location: a filled dot with a white ring.
Widget _meDot(ColorScheme scheme) {
  return SizedBox(
    width: 22,
    height: 22,
    child: Center(
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 2,
            ),
          ],
        ),
      ),
    ),
  );
}

/// The user's own-location dot as a standalone widget, for rendering via a
/// [WidgetLayer] instead of a GL symbol. Drawn by Flutter, it can't be dropped
/// by symbol collision/placement at low zoom, so "my position" stays visible at
/// every zoom level (X2).
class MeLocationDot extends StatelessWidget {
  const MeLocationDot({super.key});

  static const Size markerSize = Size(24, 24);

  @override
  Widget build(BuildContext context) => _meDot(Theme.of(context).colorScheme);
}

/// The cluster bubble background; the count is drawn on top via the layer's
/// text field.
Widget _clusterBubble(ColorScheme scheme) {
  return SizedBox(
    width: 40,
    height: 40,
    child: Center(
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
          border: Border.all(color: scheme.surface, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    ),
  );
}

/// (Re)registers every custom marker image on a freshly (re)loaded style.
/// MUST be called on each style load — the initial one and again after every
/// [MapController.setStyle] (e.g. when the app theme flips light/dark), because
/// a style reload drops previously added images.
Future<void> registerStigmaImages(
  StyleController style,
  ColorScheme scheme,
) async {
  await Future.wait([
    // Stop pins carry the colour of the transport type they serve (D1); a stop
    // with several types gets one unified "mixed" pin (D2). Hollow-disc shape
    // keeps them clearly distinct from the solid moving-vehicle pills (D3).
    style.addImageFromWidget(
      id: MapImages.bus,
      widget: _stopPin(
        vehicleGlyph(VehicleType.bus, size: 20, color: _busColor),
        _busColor,
        scheme,
      ),
    ),
    style.addImageFromWidget(
      id: MapImages.tram,
      widget: _stopPin(
        vehicleGlyph(VehicleType.tram, size: 20, color: _tramColor),
        _tramColor,
        scheme,
      ),
    ),
    style.addImageFromWidget(
      id: MapImages.trolley,
      widget: _stopPin(
        vehicleGlyph(VehicleType.trolleybus, size: 20, color: _trolleyColor),
        _trolleyColor,
        scheme,
      ),
    ),
    style.addImageFromWidget(
      id: MapImages.mixedStop,
      widget: _stopPin(
        mixedStopGlyph(size: 20, color: _mixedStopColor),
        _mixedStopColor,
        scheme,
      ),
    ),
    style.addImageFromWidget(
      id: MapImages.favorite,
      widget: _stopPin(
        const Icon(Icons.star_rounded, size: 20, color: Color(0xFFF6A609)),
        const Color(0xFFF6A609),
        scheme,
      ),
    ),
    style.addImageFromWidget(
      id: MapImages.place,
      widget: _stopPin(
        const Icon(Icons.place, size: 20, color: Color(0xFFE5484D)),
        const Color(0xFFE5484D),
        scheme,
      ),
    ),
    style.addImageFromWidget(
      id: MapImages.vehicle,
      widget: _vehiclePin(Icons.directions_bus_rounded, scheme.primary, scheme),
    ),
    style.addImageFromWidget(id: MapImages.me, widget: _meDot(scheme)),
    style.addImageFromWidget(
      id: MapImages.cluster,
      widget: _clusterBubble(scheme),
    ),
  ]);
}

/// The image id for a moving-vehicle marker of a given type.
String vehicleImageFor(VehicleType type) => MapImages.vehicle;

// ---- Live vehicle markers ---------------------------------------------------

/// Brand colour of a moving-vehicle marker, keyed by type.
///
/// Buses are the Belgrade transit blue, trolleybuses orange, trams red — a
/// base per-type distinction (C1). Colouring a tram by its *real* carriage
/// livery still sits on top of this as a deferred feature that depends on
/// resolving the vehicle model from its garage number — see the killer-feature
/// plan. When that lands, pass [tramOverride] to recolour an individual tram;
/// the rest of the marker pipeline already flows the colour through unchanged.
const _busColor = Color(0xFF1B67C4); // transit blue
const _trolleyColor = Color(0xFFEF7B22); // orange
const _tramColor = Color(0xFFD3342B); // tram red (Belgrade livery)
const _mixedStopColor = Color(0xFF5B6B7A); // multi-type stop, neutral slate
const _stuckColor = Color(0xFFB00842); // "looks stuck": deep crimson, ≠ tram red

Color vehicleColor(VehicleType type, {Color? tramOverride}) => switch (type) {
  VehicleType.bus => _busColor,
  VehicleType.trolleybus => _trolleyColor,
  VehicleType.tram => tramOverride ?? _tramColor,
};

/// An informative live-vehicle marker rendered as a real Flutter widget on the
/// map (via [WidgetLayer]): a coloured pill carrying the type glyph and line
/// number — like the number capsules in Yandex/Google transit.
///
/// Movement state, derived from our own tracking (not any traffic API), is
/// shown on the pill itself:
///  * moving  → a soft halo *breathes* around it (alive);
///  * stuck   → the halo stops pulsing and turns red (looks stuck).
class VehicleMarker extends StatefulWidget {
  const VehicleMarker({
    super.key,
    required this.line,
    required this.type,
    required this.color,
    this.heading,
    this.stuck = false,
    this.selected = false,
    this.compact = false,
    this.animate = true,
    this.onTap,
  });

  final String line;
  final VehicleType type;
  final Color color;

  /// Whether the "breathing" halo should keep pulsing. False when the vehicle
  /// layer is idle (no positions easing) so a screen full of stationary markers
  /// doesn't hold the compositor at 60fps forever — the single biggest source
  /// of steady CPU/GPU load, and heat, on the web build (thermal fix). When
  /// false the halo rests on a calm static frame instead of animating.
  final bool animate;

  /// Travel direction in degrees (0 = north, clockwise). When set, a small
  /// arrow orbits the pill pointing where the vehicle is heading.
  final double? heading;

  final bool stuck;
  final bool selected;

  /// Progressive detail (B2): at far-out zoom render just a coloured dot (the
  /// type colour, no line number) so a dense city reads as "where each type
  /// clusters" instead of a wall of number pills; up close, the full pill.
  final bool compact;

  final VoidCallback? onTap;

  /// The fixed box a [WidgetLayer] `Marker` must reserve for this widget. Tall
  /// enough to give the orbiting direction arrow clearance around the pill.
  static const Size markerSize = Size(120, 96);

  @override
  State<VehicleMarker> createState() => _VehicleMarkerState();
}

class _VehicleMarkerState extends State<VehicleMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  // The halo breathes only for a live, moving vehicle: not when it's flagged
  // stuck (steady red instead) and not when the layer is idle (thermal).
  bool get _shouldPulse => widget.animate && !widget.stuck;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (_shouldPulse) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant VehicleMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_shouldPulse) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else if (_pulse.isAnimating) {
      // Settle on a calm resting frame (t=0) rather than freezing mid-breath.
      _pulse.reset();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final haloColor = widget.stuck ? _stuckColor : widget.color;
    final heading = widget.heading;
    return SizedBox.fromSize(
      size: VehicleMarker.markerSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (heading != null && !widget.compact)
            // The direction "beak": a small arrow that orbits the pill pointing
            // where the vehicle is heading. It's offset well clear of the pill
            // so it reads as a distinct direction indicator, not fused into the
            // bubble as one lopsided blob (F4). The whole layer rotates to the
            // heading, so the beak points outward along travel while the pill's
            // number stays upright.
            Positioned.fill(
              child: Transform.rotate(
                angle: heading * (math.pi / 180),
                child: Center(
                  child: Transform.translate(
                    offset: const Offset(0, -30),
                    child: _beak(widget.stuck ? _stuckColor : widget.color),
                  ),
                ),
              ),
            ),
          GestureDetector(
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              // Breathing glow: spread pulses out while fading. Stuck vehicles
              // hold a steady soft red glow instead.
              final t = _pulse.value;
              final spread = widget.stuck ? 2.5 : 1.0 + t * 6.0;
              final glowOpacity = widget.stuck ? 0.55 : (1 - t) * 0.5;
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: haloColor.withValues(alpha: glowOpacity),
                      blurRadius: widget.stuck ? 6 : 4 + t * 8,
                      spreadRadius: spread,
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: widget.compact ? _dot(scheme) : _pill(scheme),
          ),
          ),
        ],
      ),
    );
  }

  /// The directional beak (bubble tail): a filled triangle in the pill colour
  /// with a white outline, apex pointing up (outward) when unrotated. Placed
  /// flush against the pill so it reads as part of the marker.
  Widget _beak(Color color) {
    return SizedBox(
      width: 18,
      height: 12,
      child: CustomPaint(painter: _BeakPainter(fill: color)),
    );
  }

  /// The full number pill. Compact vertical layout (E2): the type glyph sits
  /// directly above the line number so the bubble stays tight instead of
  /// stretching wide. No warning glyph — a stuck vehicle is signalled by colour
  /// alone (E3), never a `⚠` on the pill.
  Widget _pill(ColorScheme scheme) {
    final borderColor = widget.stuck
        ? _stuckColor
        : (widget.selected ? scheme.onSurface : Colors.white);
    final fill = widget.stuck ? _stuckColor : widget.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: widget.selected || widget.stuck ? 2.5 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          vehicleGlyph(widget.type, size: 13, color: Colors.white),
          Text(
            widget.line,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }

  /// The far-zoom dot (B2): a small type-coloured disc, no number. Turns the
  /// stuck colour when the vehicle looks stuck (E3/E4 — colour, not a badge).
  Widget _dot(ColorScheme scheme) {
    final fill = widget.stuck ? _stuckColor : widget.color;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(
          color: widget.selected ? scheme.onSurface : Colors.white,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

/// Paints the marker's direction beak — a filled triangle (apex up) with a
/// white outline, so rotated into place it looks like the pointed tail of the
/// marker bubble rather than a separate arrow.
class _BeakPainter extends CustomPainter {
  const _BeakPainter({required this.fill});

  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0) // apex, pointing outward
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_BeakPainter oldDelegate) => oldDelegate.fill != fill;
}
