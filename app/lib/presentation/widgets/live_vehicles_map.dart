import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre/maplibre.dart';

import '../../core/map_style.dart';
import '../../core/map_support.dart';
import '../../core/vehicle_track_animator.dart';
import '../../domain/models/arrival.dart';

/// Animated vehicle markers for the arrivals approaching a stop, rendered on a
/// MapLibre vector map. The conservative-interpolation logic lives in
/// [VehicleTrackAnimator]; here we only push the interpolated positions into a
/// GeoJSON source each animation tick (no widget rebuild).
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

class _LiveVehiclesMapState extends State<LiveVehiclesMap>
    with SingleTickerProviderStateMixin {
  static const _vehiclesSource = 'live-vehicles';

  late final AnimationController _anim;
  final _animator = VehicleTrackAnimator();

  StyleController? _style;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: widget.animationDuration)
      ..addListener(_pushVehicles);
    _animator.sync(widget.arrivals, _anim.value);
    _anim.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant LiveVehiclesMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.arrivals, widget.arrivals)) {
      _animator.sync(widget.arrivals, _anim.value);
      _anim.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Geographic get _stop => Geographic(
    lon: widget.stopLocation.longitude,
    lat: widget.stopLocation.latitude,
  );

  Future<void> _onStyleLoaded(StyleController style) async {
    _style = style;
    await registerStigmaImages(style, Theme.of(context).colorScheme);
    await style.addSource(
      GeoJsonSource(id: _vehiclesSource, data: _vehiclesGeoJson()),
    );
    await style.addLayer(
      const SymbolStyleLayer(
        id: _vehiclesSource,
        sourceId: _vehiclesSource,
        layout: {
          'icon-image': MapImages.vehicle,
          'icon-size': 0.5,
          'icon-allow-overlap': true,
          'icon-ignore-placement': true,
        },
      ),
    );
    if (mounted) setState(() => _ready = true);
  }

  void _pushVehicles() {
    _style?.updateGeoJsonSource(id: _vehiclesSource, data: _vehiclesGeoJson());
  }

  String _vehiclesGeoJson() {
    final features = [
      for (final entry in _animator.currentPositions(_anim.value))
        {
          'type': 'Feature',
          'properties': {'key': entry.key},
          'geometry': {
            'type': 'Point',
            'coordinates': [entry.value.longitude, entry.value.latitude],
          },
        },
    ];
    return jsonEncode({'type': 'FeatureCollection', 'features': features});
  }

  @override
  Widget build(BuildContext context) {
    if (!kMapRenderingEnabled) return const SizedBox.shrink();
    return MapResizeNudge(
      child: MapLibreMap(
        options: MapOptions(
          initCenter: _stop,
          initZoom: 14,
          initStyle: MapStyle.forBrightness(Theme.of(context).brightness),
        ),
        onStyleLoaded: _onStyleLoaded,
        layers: [
          if (_ready)
            MarkerLayer(
              points: [Feature<Point>(geometry: Point(_stop))],
              iconImage: MapImages.place,
              iconSize: 0.5,
              iconAnchor: IconAnchor.bottom,
              iconAllowOverlap: true,
            ),
        ],
        children: const [SourceAttribution()],
      ),
    );
  }
}
