import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';

import '../domain/models/stop.dart';
import '../domain/models/vehicle_type.dart';

// Belgrade line-number → vehicle-type heuristic. The stops feed only carries
// line numbers (not a per-stop vehicle type), so classify by the well-known
// GSP tram and trolleybus line sets; everything else is a bus. Good enough to
// pick a stop's marker icon.
const _tramLines = {'2', '3', '5', '6', '7', '9', '10', '11', '12', '13', '14'};
const _trolleyLines = {'19', '21', '22', '28', '29', '40', '41'};

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

IconData _vehicleIcon(VehicleType type) => switch (type) {
  VehicleType.bus => Icons.directions_bus_rounded,
  VehicleType.tram => Icons.tram_rounded,
  VehicleType.trolleybus => Icons.directions_bus_filled_rounded,
};

/// A clean circular stop pin: a white disc with a thin colored ring and the
/// transport-type glyph inside — deliberately not a default map balloon.
Widget _stopPin(IconData icon, Color color, ColorScheme scheme) {
  return SizedBox(
    width: 40,
    height: 40,
    child: Center(
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: scheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Icon(icon, color: color, size: 18),
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
    style.addImageFromWidget(
      id: MapImages.bus,
      widget: _stopPin(Icons.directions_bus_rounded, scheme.primary, scheme),
    ),
    style.addImageFromWidget(
      id: MapImages.tram,
      widget: _stopPin(Icons.tram_rounded, scheme.primary, scheme),
    ),
    style.addImageFromWidget(
      id: MapImages.trolley,
      widget: _stopPin(
        Icons.directions_bus_filled_rounded,
        scheme.primary,
        scheme,
      ),
    ),
    style.addImageFromWidget(
      id: MapImages.favorite,
      widget: _stopPin(Icons.star_rounded, const Color(0xFFF6A609), scheme),
    ),
    style.addImageFromWidget(
      id: MapImages.place,
      widget: _stopPin(Icons.place, const Color(0xFFE5484D), scheme),
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

/// Icon used when we register per-type vehicle markers later, if needed.
IconData movingVehicleIcon(VehicleType type) => _vehicleIcon(type);

// ---- Live vehicle markers ---------------------------------------------------

/// Brand colour of a moving-vehicle marker, keyed by type.
///
/// Buses are the Belgrade transit blue, trolleybuses orange. Trams are a single
/// neutral colour *for now*: colouring a tram by its real carriage livery
/// (red/blue/green) is a deferred feature that depends on resolving the vehicle
/// model from its garage number — see the killer-feature plan. When that lands,
/// pass [tramOverride] to recolour an individual tram; the rest of the marker
/// pipeline already flows the colour through unchanged.
const _busColor = Color(0xFF1B67C4); // transit blue
const _trolleyColor = Color(0xFFEF7B22); // orange
const _tramColor = Color(0xFF4A5A6A); // neutral slate (future: by model)
const _stuckColor = Color(0xFFE5484D); // "looks stuck" red

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
    this.onTap,
  });

  final String line;
  final VehicleType type;
  final Color color;

  /// Travel direction in degrees (0 = north, clockwise). When set, a small
  /// arrow orbits the pill pointing where the vehicle is heading.
  final double? heading;

  final bool stuck;
  final bool selected;
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

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (!widget.stuck) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant VehicleMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stuck && _pulse.isAnimating) {
      _pulse.stop();
    } else if (!widget.stuck && !_pulse.isAnimating) {
      _pulse.repeat();
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
          if (heading != null)
            // Rotating this full-box layer orbits the arrow around the pill's
            // centre to the heading bearing; the arrow glyph (points up when
            // unrotated) ends up pointing outward along the direction of travel.
            Positioned.fill(
              child: Transform.rotate(
                angle: heading * (math.pi / 180),
                child: Align(
                  alignment: const Alignment(0, -0.5),
                  child: _directionArrow(widget.color),
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
            child: _pill(scheme, haloColor),
          ),
          ),
        ],
      ),
    );
  }

  /// A white-outlined navigation arrow, pointing up (north) when unrotated.
  Widget _directionArrow(Color color) {
    return SizedBox(
      width: 22,
      height: 22,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.navigation, size: 20, color: Colors.white),
          Icon(Icons.navigation, size: 14, color: color),
        ],
      ),
    );
  }

  Widget _pill(ColorScheme scheme, Color haloColor) {
    final borderColor = widget.stuck
        ? _stuckColor
        : (widget.selected ? scheme.onSurface : Colors.white);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(999),
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_vehicleIcon(widget.type), color: Colors.white, size: 15),
          const SizedBox(width: 4),
          Text(
            widget.line,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              height: 1.0,
            ),
          ),
          if (widget.stuck) ...[
            const SizedBox(width: 3),
            const Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 13),
          ],
        ],
      ),
    );
  }
}
