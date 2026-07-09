import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
/// and — since Material Icons has none — a dedicated trolleybus SVG, so each
/// type reads by shape, not colour alone. Recoloured to [color] (white on the
/// coloured pills, the type colour on stop pins).
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
      return SvgPicture.asset(
        'assets/icons/trolleybus.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
  }
}
