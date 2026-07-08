import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../domain/models/stop.dart';

const _belgradeCenter = ll.LatLng(44.8125, 20.4612);

/// Shows stop markers on an OSM map, optionally with a highlighted center
/// point (the user's location, or a geocoded street/place) and/or a route
/// polyline (a line's full trace).
class MapScreen extends StatelessWidget {
  const MapScreen({
    super.key,
    required this.stops,
    this.center,
    this.centerLabel,
    this.title,
    this.polyline,
    this.extraMarkers = const [],
  });

  final List<Stop> stops;
  final ll.LatLng? center;
  final String? centerLabel;
  final String? title;
  final List<List<double>>? polyline;
  final List<Marker> extraMarkers;

  @override
  Widget build(BuildContext context) {
    final initialCenter = center ??
        (polyline != null && polyline!.isNotEmpty
            ? ll.LatLng(polyline!.first[0], polyline!.first[1])
            : (stops.isNotEmpty ? ll.LatLng(stops.first.lat, stops.first.lon) : _belgradeCenter));

    return Scaffold(
      appBar: AppBar(title: Text(title ?? centerLabel ?? '')),
      body: FlutterMap(
        options: MapOptions(initialCenter: initialCenter, initialZoom: 14),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.theoutlines.stigla',
          ),
          if (polyline != null && polyline!.isNotEmpty)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: polyline!.map((p) => ll.LatLng(p[0], p[1])).toList(),
                  color: Theme.of(context).colorScheme.primary,
                  strokeWidth: 4,
                ),
              ],
            ),
          MarkerLayer(
            markers: [
              if (center != null)
                Marker(
                  point: center!,
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.place, color: Colors.redAccent, size: 36),
                ),
              for (final stop in stops)
                Marker(
                  point: ll.LatLng(stop.lat, stop.lon),
                  width: 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: () => context.push('/stop/${stop.stopId}?name=${Uri.encodeComponent(stop.name)}'),
                    child: Tooltip(
                      message: stop.name,
                      child: Icon(Icons.directions_bus_rounded, color: Theme.of(context).colorScheme.primary, size: 30),
                    ),
                  ),
                ),
              ...extraMarkers,
            ],
          ),
          const SimpleAttributionWidget(
            source: Text('© OpenStreetMap contributors'),
          ),
        ],
      ),
    );
  }
}
