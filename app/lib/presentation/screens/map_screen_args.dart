import 'package:latlong2/latlong.dart' as ll;

import '../../domain/models/stop.dart';

class MapScreenArgs {
  const MapScreenArgs({required this.stops, this.center, this.centerLabel, this.title});

  final List<Stop> stops;
  final ll.LatLng? center;
  final String? centerLabel;
  final String? title;
}
