import 'package:flutter/material.dart';

import '../../domain/models/vehicle_type.dart';
import '../../core/design/stize_icons.dart';

/// Plain [IconData] per type, from the Stiže icon set.
IconData vehicleIconFor(VehicleType type) {
  switch (type) {
    case VehicleType.bus:
      return StizeIcons.bus;
    case VehicleType.tram:
      return StizeIcons.tram;
    case VehicleType.trolleybus:
      return StizeIcons.trolleybus;
  }
}

/// A per-type transport glyph as a widget: bus, tram and trolleybus all from
/// the icon set (one stroke style), so each type reads by shape, not colour
/// alone. Recoloured to [color] (white on the coloured pills, the type colour
/// on stop pins).
Widget vehicleGlyph(
  VehicleType type, {
  required double size,
  required Color color,
}) => Icon(vehicleIconFor(type), size: size, color: color);

/// The glyph for a "mixed" stop: one served by more than one vehicle type
/// (e.g. bus + trolleybus). Two buses, one behind the other, read as "several
/// lines here" without stacking separate pins. Drawn in the icon set's style.
Widget mixedStopGlyph({required double size, required Color color}) =>
    Icon(StizeIcons.busMultiple, size: size, color: color);
