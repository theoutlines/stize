import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/vehicle_type.dart';

/// Plain [IconData] per type — for the few places that only need a glyph code.
/// Note: Material Icons has no trolleybus, so trolleybus falls back to a bus
/// here; prefer [vehicleGlyph] where a real per-type shape matters.
IconData vehicleIconFor(VehicleType type) {
  switch (type) {
    case VehicleType.bus:
      return Icons.directions_bus_rounded;
    case VehicleType.tram:
      return Icons.tram_rounded;
    case VehicleType.trolleybus:
      return Icons.directions_bus_filled_rounded;
  }
}

/// A per-type transport glyph as a widget: a bus for buses, a tram for trams,
/// and — since Material Icons has none — a *composed* trolleybus (a bus body
/// with two trolley poles reaching up to the wire) so each type reads by shape,
/// not colour alone.
Widget vehicleGlyph(
  VehicleType type, {
  required double size,
  required Color color,
}) {
  switch (type) {
    case VehicleType.bus:
      return Icon(Icons.directions_bus_rounded, size: size, color: color);
    case VehicleType.tram:
      return Icon(Icons.tram_rounded, size: size, color: color);
    case VehicleType.trolleybus:
      return _TrolleybusGlyph(size: size, color: color);
  }
}

class _TrolleybusGlyph extends StatelessWidget {
  const _TrolleybusGlyph({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.directions_bus_rounded, size: size, color: color),
          // Poles drawn on top of the roof so they read even at small sizes.
          Positioned.fill(
            child: CustomPaint(painter: _TrolleyPolesPainter(color)),
          ),
        ],
      ),
    );
  }
}

/// Two trolley poles rising from the bus roof to a wire contact up and to the
/// right, with a small contact dot.
class _TrolleyPolesPainter extends CustomPainter {
  const _TrolleyPolesPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, s * 0.06)
      ..strokeCap = StrokeCap.round;

    final contact = Offset(s * 0.72, s * 0.10);
    canvas.drawLine(Offset(s * 0.42, s * 0.32), contact, paint);
    canvas.drawLine(Offset(s * 0.55, s * 0.32), contact, paint);
    canvas.drawCircle(contact, math.max(0.8, s * 0.05), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrolleyPolesPainter oldDelegate) =>
      oldDelegate.color != color;
}
