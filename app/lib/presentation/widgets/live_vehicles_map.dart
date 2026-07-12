import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre/maplibre.dart';

import '../../core/map_style.dart';
import '../../core/map_support.dart';
import '../../core/vehicle_route.dart';
import '../../core/vehicle_track_animator.dart';
import '../../domain/models/arrival.dart';
import '../../domain/models/route_shape.dart';
import '../providers/providers.dart';
import 'vehicle_detail_sheet.dart';

/// Animated live-vehicle markers for the arrivals approaching a stop, on a
/// MapLibre vector map. The conservative-interpolation logic lives in
/// [VehicleTrackAnimator]; here we render each vehicle as an informative pill
/// ([VehicleMarker]) that tracks the map, and let a tap highlight the line's
/// trace and open a detail sheet ([showVehicleDetailSheet]).
class LiveVehiclesMap extends ConsumerStatefulWidget {
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
  ConsumerState<LiveVehiclesMap> createState() => _LiveVehiclesMapState();
}

class _LiveVehiclesMapState extends ConsumerState<LiveVehiclesMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  final _animator = VehicleTrackAnimator();

  // key -> arrival, so a tapped vehicle can read its ETA / stops-remaining.
  Map<String, Arrival> _arrivalByKey = {};

  bool _imagesReady = false;

  // Selection state: the highlighted vehicle and its computed route trace.
  String? _selectedKey;
  VehicleRoutePlan? _plan;
  Color? _selectedColor;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: widget.animationDuration);
    _syncArrivals();
    _playEase();
  }

  @override
  void didUpdateWidget(covariant LiveVehiclesMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.arrivals, widget.arrivals)) {
      _syncArrivals();
      _playEase();
    }
  }

  /// Ease toward the new fixes only when there's actual motion to show; a set of
  /// stationary vehicles settles instantly so the map holds at zero frames
  /// instead of running the controller (and every marker's halo) for the whole
  /// interval (thermal — "idle = 0 frames").
  void _playEase() {
    if (_animator.hasPendingMotion) {
      _anim.forward(from: 0);
    } else {
      _anim.value = 1;
    }
  }

  void _syncArrivals() {
    _animator.sync(widget.arrivals, _anim.value);
    _arrivalByKey = {
      for (final a in widget.arrivals)
        if (a.gps != null) VehicleTrackAnimator.keyFor(a): a,
    };
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
    await registerStigmaImages(style, Theme.of(context).colorScheme);
    if (mounted) setState(() => _imagesReady = true);
  }

  // ---- Tap: highlight trace + open the detail sheet -------------------------

  Future<void> _onVehicleTap(String key) async {
    final track = _animator.trackFor(key);
    final arrival = _arrivalByKey[key];
    if (track == null || arrival == null) return;

    setState(() => _selectedKey = key);

    RouteShape shape;
    try {
      shape = await ref
          .read(linesRepositoryProvider)
          .getShapeByLineNumber(track.line);
    } catch (_) {
      return; // keep the marker selected; just no trace/sheet on failure
    }
    if (!mounted) return;

    final plan = planVehicleRoute(
      shape: shape,
      vehicle: track.to, // latest real fix, best anchor for projection
      boardStop: widget.stopLocation,
      stopsRemaining: arrival.stopsRemaining,
      etaToBoardMinutes: arrival.etaMinutes,
    );
    setState(() {
      _plan = plan;
      _selectedColor = vehicleColor(track.type);
    });

    await showVehicleDetailSheet(
      context,
      line: track.line,
      type: track.type,
      color: vehicleColor(track.type),
      stuck: _animator.isStuck(key),
      shape: shape,
      plan: plan,
    );
    if (mounted) {
      setState(() {
        _selectedKey = null;
        _plan = null;
        _selectedColor = null;
      });
    }
  }

  // ---- Build ----------------------------------------------------------------

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
        layers: _mapLayers(context),
        children: [
          const CompactAttribution(),
          // Live vehicles, rebuilt each animation tick so their eased positions
          // update; only this subtree repaints, not the whole map.
          AnimatedBuilder(
            animation: _anim,
            builder: (context, _) =>
                WidgetLayer(markers: _vehicleMarkers(), allowInteraction: true),
          ),
        ],
      ),
    );
  }

  List<Layer> _mapLayers(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;
    final bright = _selectedColor ?? theme.colorScheme.primary;
    final dim = theme.colorScheme.outline.withValues(alpha: 0.55);
    return [
      // Selected vehicle's trace, under the markers: traveled part dim,
      // upcoming part bright.
      if (plan != null && plan.traveled.length >= 2)
        PolylineLayer(
          polylines: [
            Feature<LineString>(
              geometry: LineString.from([
                for (final p in plan.traveled) Geographic(lon: p[1], lat: p[0]),
              ]),
            ),
          ],
          color: dim,
          width: 4,
        ),
      if (plan != null && plan.upcoming.length >= 2)
        PolylineLayer(
          polylines: [
            Feature<LineString>(
              geometry: LineString.from([
                for (final p in plan.upcoming) Geographic(lon: p[1], lat: p[0]),
              ]),
            ),
          ],
          color: bright,
          width: 5,
        ),
      // Stop pin (static), above the trace.
      if (_imagesReady)
        MarkerLayer(
          points: [Feature<Point>(geometry: Point(_stop))],
          iconImage: MapImages.place,
          iconSize: 0.5,
          iconAnchor: IconAnchor.bottom,
          iconAllowOverlap: true,
        ),
    ];
  }

  List<Marker> _vehicleMarkers() {
    final markers = <Marker>[];
    for (final entry in _animator.currentPositions(_anim.value)) {
      final key = entry.key;
      final track = _animator.trackFor(key);
      if (track == null) continue;
      final pos = entry.value;
      markers.add(
        Marker(
          point: Geographic(lon: pos.longitude, lat: pos.latitude),
          size: VehicleMarker.markerSize,
          child: VehicleMarker(
            key: ValueKey(key),
            line: track.line,
            type: track.type,
            color: vehicleColor(track.type),
            heading: track.heading,
            stuck: _animator.isStuck(key),
            selected: key == _selectedKey,
            // Halo breathes only while the ease is in flight; rests once settled.
            animate: _anim.isAnimating,
            onTap: () => _onVehicleTap(key),
          ),
        ),
      );
    }
    return markers;
  }
}
