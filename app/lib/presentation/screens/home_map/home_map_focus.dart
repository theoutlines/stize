part of '../home_map_screen.dart';

// The focused line on the map: its route and its stops as imperative layers
// under the vehicle symbols.

extension _MapFocus on _HomeMapScreenState {
  /// (Re)build the focused-line layers imperatively: the route line (in its type
  /// colour) and that line's own stops, both inserted *below* the vehicle badge
  /// so the followed coin stays on top. Removes them when there's no focus. The
  /// route layer is recreated per focus because its colour is baked into the
  /// layer paint. Best-effort: a failure just leaves the route un-highlighted.
  Future<void> _syncFocusLayers() async {
    final style = _style;
    if (style == null) return;
    // Tear down any previous focus layers first (colour/route may have changed).
    if (_focusLayersAdded) {
      for (final id in const [
        _HomeMapScreenState._focusRouteLayerId,
        _HomeMapScreenState._focusStopsLayerId,
      ]) {
        try {
          await style.removeLayer(id);
        } catch (_) {}
        try {
          await style.removeSource(_stopSourceId(id));
        } catch (_) {}
      }
      _focusLayersAdded = false;
    }
    final focus = _focus;
    if (focus == null) return;
    final below = focusInsertBelowLayerId(vehicleLayersAdded: _vehLayerAdded);
    try {
      if (focus.polyline.length >= 2) {
        final srcId = _stopSourceId(_HomeMapScreenState._focusRouteLayerId);
        await style.addSource(
          GeoJsonSource(id: srcId, data: _focusRouteGeoJson(focus)),
        );
        final line = PolylineLayer(
          polylines: const [],
          color: vehicleColor(focus.type),
          width: 5,
        );
        await style.addLayer(
          LineStyleLayer(
            id: _HomeMapScreenState._focusRouteLayerId,
            sourceId: srcId,
            layout: line.getLayout(),
            paint: line.getPaint(),
          ),
          belowLayerId: below,
        );
      }
      final stopsSrc = _stopSourceId(_HomeMapScreenState._focusStopsLayerId);
      await style.addSource(
        GeoJsonSource(id: stopsSrc, data: _focusStopsGeoJson(focus)),
      );
      final pin = MarkerLayer(
        points: const [],
        iconImage: MapImages.forStop(focus.type),
        iconSize: _HomeMapScreenState._iconSize,
        iconAllowOverlap: true,
      );
      await style.addLayer(
        SymbolStyleLayer(
          id: _HomeMapScreenState._focusStopsLayerId,
          sourceId: stopsSrc,
          layout: pin.getLayout(),
          paint: pin.getPaint(),
        ),
        belowLayerId: below,
      );
      _focusLayersAdded = true;
      _focusLayerError = null;
    } catch (e) {
      // Don't swallow silently — a failed focus-stops add is exactly the class
      // of "the route line draws but its stop pins don't" bug. debugPrint is
      // stripped in release web, so surface it on the staging overlay instead
      // (the reliable render-debug channel on Flutter-CanvasKit).
      _focusLayerError = '$e';
      _focusLayersAdded = false;
    }
  }

  String _focusRouteGeoJson(_LineFocus focus) => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          // focus.polyline is [lat, lon]; GeoJSON is [lon, lat].
          'coordinates': [
            for (final p in focus.polyline) [p[1], p[0]],
          ],
        },
        'properties': const <String, dynamic>{},
      },
    ],
  });

  String _focusStopsGeoJson(_LineFocus focus) => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final s in focus.stops)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [s.lon, s.lat],
          },
          // Only stopId (the tap handler looks the name up) — jsonEncode escapes
          // it correctly regardless, but the name isn't needed here.
          'properties': {'stopId': s.stopId},
        },
    ],
  });
}
