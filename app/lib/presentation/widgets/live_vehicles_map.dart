import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/vehicle_track_animator.dart';
import '../../domain/models/arrival.dart';

/// Animated vehicle markers for the arrivals currently approaching a stop.
/// See [VehicleTrackAnimator] for the conservative-interpolation rule.
class LiveVehiclesMap extends StatefulWidget {
  const LiveVehiclesMap({
    super.key,
    required this.arrivals,
    required this.stopLocation,
    this.animationDuration = const Duration(seconds: 25),
  });

  final List<Arrival> arrivals;
  final ll.LatLng stopLocation;
  final Duration animationDuration;

  @override
  State<LiveVehiclesMap> createState() => _LiveVehiclesMapState();
}

class _LiveVehiclesMapState extends State<LiveVehiclesMap> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final _animator = VehicleTrackAnimator();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.animationDuration);
    _animator.sync(widget.arrivals, _controller.value);
    _controller.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant LiveVehiclesMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.arrivals, widget.arrivals)) {
      _animator.sync(widget.arrivals, _controller.value);
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final primary = Theme.of(context).colorScheme.primary;
        final markers = <Marker>[
          Marker(
            point: widget.stopLocation,
            width: 30,
            height: 30,
            child: const Icon(Icons.location_on, color: Colors.redAccent, size: 28),
          ),
          for (final entry in _animator.currentPositions(_controller.value))
            Marker(
              point: entry.value,
              width: 32,
              height: 32,
              child: Icon(Icons.directions_bus_rounded, color: primary, size: 26),
            ),
        ];
        return FlutterMap(
          options: MapOptions(initialCenter: widget.stopLocation, initialZoom: 14),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.theoutlines.stigla',
            ),
            MarkerLayer(markers: markers),
          ],
        );
      },
    );
  }
}
