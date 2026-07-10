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
      // The trolleybus artwork nearly fills its 24×24 viewBox (the poles reach
      // the top edge), so at 1:1 it reads larger than the Material glyphs and
      // touches the pin's rim. Draw it a touch smaller, centred in the same
      // footprint, to match the bus/tram weight and keep clear of the edge.
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: SvgPicture.asset(
            'assets/icons/trolleybus.svg',
            width: size * 0.82,
            height: size * 0.82,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
        ),
      );
  }
}

/// The glyph for a "mixed" stop — one served by more than one vehicle type
/// (e.g. bus + trolleybus). MDI's bus-multiple reads as "several lines here"
/// without stacking separate pins. Recoloured to [color].
Widget mixedStopGlyph({required double size, required Color color}) {
  // Like the trolleybus artwork, bus-multiple fills its viewBox edge-to-edge,
  // so draw it a little smaller and centred to keep clear of the pin's rim.
  return SizedBox(
    width: size,
    height: size,
    child: Center(
      child: SvgPicture.asset(
        'assets/icons/bus_multiple.svg',
        width: size * 0.8,
        height: size * 0.8,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      ),
    ),
  );
}
