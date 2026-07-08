import 'package:flutter/material.dart';

import '../../domain/models/vehicle_type.dart';

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
