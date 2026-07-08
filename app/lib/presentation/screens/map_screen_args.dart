import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../domain/models/stop.dart';

class MapScreenArgs {
  const MapScreenArgs({
    required this.stops,
    this.center,
    this.centerLabel,
    this.title,
    this.polyline,
    this.extraMarkers = const [],
    this.lineNumber,
  });

  final List<Stop> stops;
  final ll.LatLng? center;
  final String? centerLabel;
  final String? title;
  final List<List<double>>? polyline;
  final List<Marker> extraMarkers;
  final String? lineNumber;
}
