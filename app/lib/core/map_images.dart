part of 'map_support.dart';

// The map's registered images: stop and vehicle pins, the location dot with its heading cone, the cluster bubble, and their registration with the style.

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

/// A stop's map pin as a plain widget, for lists that show a stop the way the
/// map does (search results): the same disc, ring colour and glyph.
Widget stopPinFor(Stop stop, ColorScheme scheme) {
  final type = stopMarkerType(stop);
  final (Widget glyph, Color color) = switch (type) {
    null => (mixedStopGlyph(size: 20, color: _mixedStopColor), _mixedStopColor),
    VehicleType.bus => (
      vehicleGlyph(VehicleType.bus, size: 20, color: _busColor),
      _busColor,
    ),
    VehicleType.tram => (
      vehicleGlyph(VehicleType.tram, size: 20, color: _tramColor),
      _tramColor,
    ),
    VehicleType.trolleybus => (
      vehicleGlyph(VehicleType.trolleybus, size: 20, color: _trolleyColor),
      _trolleyColor,
    ),
  };
  return _stopPin(glyph, color, scheme);
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

/// The shortest signed turn from heading [from] to [to], in degrees
/// (-180..180]: 350° to 10° is +20°, not -340°.
double headingDelta(double from, double to) {
  var d = (to - from) % 360;
  if (d > 180) d -= 360;
  if (d <= -180) d += 360;
  return d;
}

/// The user's own-location dot as a standalone widget, for rendering via a
/// [WidgetLayer] instead of a GL symbol. Drawn by Flutter, it can't be dropped
/// by symbol collision/placement at low zoom, so "my position" stays visible at
/// every zoom level (X2).
///
/// With a compass [heading] (degrees clockwise from north) a cone shows where
/// the phone is facing, like Yandex Maps (DS LocationDot): a 70° sector, 48px,
/// the dot's colour fading from 45% to nothing. The marker turns with the map,
/// so the heading is drawn as is. It turns by the shortest way.
class MeLocationDot extends StatefulWidget {
  const MeLocationDot({super.key, this.heading});

  final double? heading;

  /// Room for the cone around the dot; the dot sits at the centre.
  static const Size markerSize = Size(112, 112);

  static const double coneRadius = 48;
  static const double coneSweep = 70;

  @override
  State<MeLocationDot> createState() => _MeLocationDotState();
}

class _MeLocationDotState extends State<MeLocationDot> {
  // Cumulative turns, so 350° → 10° animates +20° instead of spinning back.
  double _turns = 0;

  @override
  void initState() {
    super.initState();
    _turns = (widget.heading ?? 0) / 360;
  }

  @override
  void didUpdateWidget(covariant MeLocationDot old) {
    super.didUpdateWidget(old);
    final h = widget.heading;
    final prev = old.heading;
    if (h == null) return;
    _turns = prev == null ? h / 360 : _turns + headingDelta(prev, h) / 360;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.heading != null)
            AnimatedRotation(
              turns: _turns,
              duration: StizeMotion.fast,
              curve: Curves.easeOut,
              child: CustomPaint(
                size: MeLocationDot.markerSize,
                painter: _HeadingConePainter(color: scheme.primary),
              ),
            ),
          _meDot(scheme),
        ],
      ),
    );
  }
}

/// The heading cone, pointing up (north) before rotation.
class _HeadingConePainter extends CustomPainter {
  const _HeadingConePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const r = MeLocationDot.coneRadius;
    const sweep = MeLocationDot.coneSweep * math.pi / 180;
    final rect = Rect.fromCircle(center: c, radius: r);
    final path = Path()
      ..moveTo(c.dx, c.dy)
      ..arcTo(rect, -math.pi / 2 - sweep / 2, sweep, false)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_HeadingConePainter old) => old.color != color;
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

/// Image ids each map has added so far, keyed by the map's owner (its widget
/// `State`). Lets a re-registration replace images the style still holds.
final _addedImages = Expando<Set<String>>('mapImages');

/// Adds a widget-rendered image to the style, replacing the one this [owner]
/// added before under the same id.
///
/// A theme switch calls `setStyle` with the other Stiže Standard variant. The
/// two share every layer id, so MapLibre GL JS applies the change as an
/// in-place diff and fires `style.load` while keeping the images already added;
/// a plain `addImage` then only logs "already exists" and keeps the old,
/// wrongly tinted image. Removing first re-tints pins and the me-dot.
Future<void> putImageFromWidget(
  StyleController style,
  Object owner, {
  required String id,
  required Widget widget,
}) async {
  final added = _addedImages[owner] ??= <String>{};
  if (added.contains(id)) await style.removeImage(id);
  await style.addImageFromWidget(id: id, widget: widget);
  added.add(id);
}

/// (Re)registers every custom marker image on a freshly (re)loaded style.
/// MUST be called on each style load — the initial one and again after every
/// [MapController.setStyle] (e.g. when the app theme flips light/dark), because
/// a style reload drops previously added images.
Future<void> registerStigmaImages(
  StyleController style,
  ColorScheme scheme, {
  required Object owner,
}) async {
  await Future.wait([
    // Stop pins carry the colour of the transport type they serve (D1); a stop
    // with several types gets one unified "mixed" pin (D2). Hollow-disc shape
    // keeps them clearly distinct from the solid moving-vehicle pills (D3).
    putImageFromWidget(
      style,
      owner,
      id: MapImages.bus,
      widget: _stopPin(
        vehicleGlyph(VehicleType.bus, size: 20, color: _busColor),
        _busColor,
        scheme,
      ),
    ),
    putImageFromWidget(
      style,
      owner,
      id: MapImages.tram,
      widget: _stopPin(
        vehicleGlyph(VehicleType.tram, size: 20, color: _tramColor),
        _tramColor,
        scheme,
      ),
    ),
    putImageFromWidget(
      style,
      owner,
      id: MapImages.trolley,
      widget: _stopPin(
        vehicleGlyph(VehicleType.trolleybus, size: 20, color: _trolleyColor),
        _trolleyColor,
        scheme,
      ),
    ),
    putImageFromWidget(
      style,
      owner,
      id: MapImages.mixedStop,
      widget: _stopPin(
        mixedStopGlyph(size: 20, color: _mixedStopColor),
        _mixedStopColor,
        scheme,
      ),
    ),
    putImageFromWidget(
      style,
      owner,
      id: MapImages.favorite,
      widget: _stopPin(
        const Icon(StizeIcons.starFilled, size: 20, color: Color(0xFFF6A609)),
        const Color(0xFFF6A609),
        scheme,
      ),
    ),
    putImageFromWidget(
      style,
      owner,
      id: MapImages.place,
      widget: _stopPin(
        const Icon(StizeIcons.pin, size: 20, color: Color(0xFFE5484D)),
        const Color(0xFFE5484D),
        scheme,
      ),
    ),
    putImageFromWidget(
      style,
      owner,
      id: MapImages.vehicle,
      widget: _vehiclePin(StizeIcons.bus, scheme.primary, scheme),
    ),
    putImageFromWidget(style, owner, id: MapImages.me, widget: _meDot(scheme)),
    putImageFromWidget(
      style,
      owner,
      id: MapImages.cluster,
      widget: _clusterBubble(scheme),
    ),
  ]);
}
