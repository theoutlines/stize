part of 'map_support.dart';

// Live vehicle markers: colours by type and the VehicleMarker pill used by the per-stop mini-map.

// ---- Live vehicle markers ---------------------------------------------------

/// Brand colour of a moving-vehicle marker, keyed by type.
///
/// Buses are the Belgrade transit blue, trolleybuses orange, trams red — a
/// base per-type distinction (C1). Colouring a tram by its *real* carriage
/// livery still sits on top of this as a deferred feature that depends on
/// resolving the vehicle model from its garage number — see the killer-feature
/// plan. When that lands, pass [tramOverride] to recolour an individual tram;
/// the rest of the marker pipeline already flows the colour through unchanged.
const _busColor = Color(0xFF2278E6); // transit blue
const _trolleyColor = Color(
  0xFFEA7000,
); // orange (design-system transit-trolleybus)
const _tramColor = Color(0xFFE4312F); // tram red (Belgrade livery)
const _mixedStopColor = Color(0xFF5B6B7A); // multi-type stop, neutral slate
const _stuckColor = Color(
  0xFFB00842,
); // "looks stuck": deep crimson, ≠ tram red

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
    _pulse = AnimationController(vsync: this, duration: StizeMotion.loop);
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
                    borderRadius: BorderRadius.circular(StizeRadius.radiusPill),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(StizeRadius.radiusTile),
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
          vehicleGlyph(widget.type, size: 12, color: Colors.white),
          Text(
            widget.line,
            style: StizeType.lineNumber.copyWith(
              color: Colors.white,
              fontSize: 12,
              height: 1.0,
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
