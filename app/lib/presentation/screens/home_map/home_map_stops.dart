part of '../home_map_screen.dart';

// Stops for the visible area: fetch them as the camera moves, the imperative
// stop layers (one per type + mixed + clusters) and the GeoJSON pushed to them.

extension _MapStops on _HomeMapScreenState {
  double _radiusForVisibleArea(MapCamera camera) {
    try {
      final region = _controller!.getVisibleRegion();
      final ne = ll.LatLng(region.latitudeNorth, region.longitudeEast);
      final center = ll.LatLng(camera.center.lat, camera.center.lon);
      return _distance.as(ll.LengthUnit.Meter, center, ne).clamp(400.0, 3000.0);
    } catch (_) {
      return 1200;
    }
  }

  Future<void> _loadStopsForVisibleArea() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final camera = controller.getCamera();
    if (camera.zoom < _minStopsZoom) {
      if (_stops.area.isNotEmpty) {
        _stops.lastFetchCenter = null;
        _setState(() {
          _stops.area = [];
          _rebuildMarkerFeatures();
        });
      }
      return;
    }
    final center = ll.LatLng(camera.center.lat, camera.center.lon);
    final radius = _radiusForVisibleArea(camera);
    if (_stops.lastFetchCenter != null) {
      final moved = _distance.as(
        ll.LengthUnit.Meter,
        _stops.lastFetchCenter!,
        center,
      );
      if (moved < _stops.lastFetchRadius * 0.35 &&
          (radius - _stops.lastFetchRadius).abs() <
              _stops.lastFetchRadius * 0.5) {
        // Barely moved — still recluster (zoom may have changed) but skip refetch.
        _setState(_rebuildMarkerFeatures);
        return;
      }
    }
    final seq = ++_stops.requestSeq;
    _stops.lastFetchCenter = center;
    _stops.lastFetchRadius = radius;
    try {
      final stops = await ref
          .read(stopsRepositoryProvider)
          .nearby(
            lat: center.latitude,
            lon: center.longitude,
            radiusMeters: radius,
          );
      if (!mounted || seq != _stops.requestSeq) return;
      _setState(() {
        _stops.area = stops;
        _rebuildMarkerFeatures();
      });
    } catch (_) {
      // Keep whatever is shown on a transient failure.
    }
  }

  String _stopSourceId(String layerId) => '$layerId-src';

  /// Adds the stop marker layers + their (empty) GeoJSON sources to a freshly
  /// loaded style, once. Styling is taken from the same MarkerLayer/PolylineLayer
  /// specs the declarative path used, so the pins look identical. Order = paint
  /// order (first added sits lowest): rails · cluster · bus · tram · trolley ·
  /// mixed · favourites · pinned place. Data arrives later via
  /// [_pushStopSources]; the layers themselves are never removed/re-added, so the
  /// buggy positional reconcile can't drop them.
  Future<void> _addStopLayers(StyleController style) async {
    if (_stops.layersAdded || _stops.layersAdding) return;
    _stops.layersAdding = true;
    MarkerLayer pin(String image, {IconAnchor anchor = IconAnchor.center}) =>
        MarkerLayer(
          points: const [],
          iconImage: image,
          iconSize: _HomeMapScreenState._iconSize,
          iconAllowOverlap: true,
          iconAnchor: anchor,
        );
    final specs = <(String, Layer)>[
      (
        _LayerIds.rails,
        const PolylineLayer(polylines: [], color: tramRailColor, width: 2),
      ),
      (
        _LayerIds.cluster,
        MarkerLayer(
          points: const [],
          iconImage: MapImages.cluster,
          iconSize: _HomeMapScreenState._iconSize,
          iconAllowOverlap: true,
          textField: '{point_count}',
          textColor: _scheme.onPrimary,
          textSize: 13,
          textAllowOverlap: true,
        ),
      ),
      (_LayerIds.bus, pin(MapImages.bus)),
      (_LayerIds.tram, pin(MapImages.tram)),
      (_LayerIds.trolley, pin(MapImages.trolley)),
      (_LayerIds.mixed, pin(MapImages.mixedStop)),
      (_LayerIds.fav, pin(MapImages.favorite)),
      (_LayerIds.place, pin(MapImages.place, anchor: IconAnchor.bottom)),
    ];
    try {
      for (final (id, tmpl) in specs) {
        final srcId = _stopSourceId(id);
        await style.addSource(
          GeoJsonSource(id: srcId, data: _LayerIds.emptyFeatureCollection),
        );
        final StyleLayer layer = tmpl is PolylineLayer
            ? LineStyleLayer(
                id: id,
                sourceId: srcId,
                layout: tmpl.getLayout(),
                paint: tmpl.getPaint(),
              )
            : SymbolStyleLayer(
                id: id,
                sourceId: srcId,
                layout: (tmpl as MarkerLayer).getLayout(),
                paint: tmpl.getPaint(),
              );
        await style.addLayer(layer);
      }
      // Flip the ready flag ONLY once every source exists, so a camera-idle
      // firing mid-add can't call updateGeoJsonSource on a not-yet-created
      // source (that used to throw and poison the whole push — the stop pins
      // then never came back until the data happened to change).
      _stops.layersAdded = true;
    } catch (_) {
      // Style torn down mid-add (e.g. a theme flip) — allow a later retry.
      _stops.layersAdded = false;
    } finally {
      _stops.layersAdding = false;
    }
  }

  /// Pushes the current marker feature lists into the imperative stop layers'
  /// sources. Only source *data* changes — no layers are added or removed — so
  /// the reconcile bug can never drop a layer. Every source is (re)pushed on
  /// each call so a source can never get stuck on stale/empty data.
  /// Coalesces stop-layer pushes: several triggers in a burst (style load,
  /// line-type index, rails, area stops, favourites) rebuild and re-upload the
  /// GeoJSON once, on the next tick, instead of once per trigger. Each push
  /// serialises every stop and makes MapLibre re-parse it on the main thread.
  void _pushStopSources() {
    if (_stops.pushTimer?.isActive ?? false) return;
    _stops.pushTimer = Timer(const Duration(milliseconds: 32), () {
      if (mounted) _pushStopSourcesNow();
    });
  }

  void _pushStopSourcesNow() {
    final style = _style;
    if (style == null || !_stops.layersAdded) return;
    // While a line is focused, only its own route shows (via the declarative
    // focus layers) — empty every ambient stop source so nothing else competes.
    // Also hide the stops when the coverage heatmap stands in for them (flag on +
    // zoomed out); the heatmap shows through.
    final focused = _focus != null;
    final zoom = _controller?.getCamera().zoom ?? 15.0;
    final hidden =
        focused || (_cov.enabled && coverageMainStopsOpacity(zoom) <= 0.01);
    final favStops =
        ref.read(favoriteStopLocationsProvider).valueOrNull ?? const <Stop>[];
    // Serialise via `jsonEncode`, NOT geobase's `FeatureCollection.toText()`:
    // toText() does not escape `"` (and other specials) in string properties, so
    // a stop whose name contains a quote — e.g. `Park "Tašmajdan"` (19 such stops
    // in the feed) — produced invalid JSON, which the web plugin's
    // `setData(JSON.parse(data))` threw on, leaving that source empty and its
    // stops unrendered. `jsonEncode` escapes correctly.
    String pointsFc(List<Feature<Point>> f) {
      if (hidden) return _LayerIds.emptyFeatureCollection;
      return jsonEncode({
        'type': 'FeatureCollection',
        'features': [
          for (final feature in f)
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [
                  feature.geometry!.position.x,
                  feature.geometry!.position.y,
                ],
              },
              'properties': feature.properties,
            },
        ],
      });
    }

    Map<String, Object?> stopFeature(Stop s) => {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [s.lon, s.lat],
      },
      'properties': {'stopId': s.stopId, 'name': s.name},
    };
    final data = <String, String>{
      _LayerIds.rails: focused
          ? _LayerIds.emptyFeatureCollection
          : jsonEncode({
              'type': 'FeatureCollection',
              'features': [
                for (final poly in _stops.rails)
                  {
                    'type': 'Feature',
                    'geometry': {
                      'type': 'LineString',
                      'coordinates': [
                        for (final p in poly) [p[1], p[0]],
                      ],
                    },
                    'properties': const <String, Object?>{},
                  },
              ],
            }),
      _LayerIds.cluster: pointsFc(_stops.clusterPts),
      _LayerIds.bus: pointsFc(_stops.busPts),
      _LayerIds.tram: pointsFc(_stops.tramPts),
      _LayerIds.trolley: pointsFc(_stops.trolleyPts),
      _LayerIds.mixed: pointsFc(_stops.mixedPts),
      _LayerIds.fav: focused
          ? _LayerIds.emptyFeatureCollection
          : jsonEncode({
              'type': 'FeatureCollection',
              'features': [for (final s in favStops) stopFeature(s)],
            }),
      _LayerIds.place: focused
          ? _LayerIds.emptyFeatureCollection
          : jsonEncode({
              'type': 'FeatureCollection',
              'features': [
                if (_pinnedPlace case final place?)
                  {
                    'type': 'Feature',
                    'geometry': {
                      'type': 'Point',
                      'coordinates': [place.lon, place.lat],
                    },
                    'properties': const <String, Object?>{},
                  },
              ],
            }),
    };
    // Always push every source (no dedup cache): `updateGeoJsonSource` is a
    // synchronous `setData` on web, so re-pushing unchanged data on a camera
    // idle is cheap, and it guarantees a source that briefly failed an earlier
    // push (or was reset) always recovers on the next one. Each update is
    // isolated so one failure can't abort the rest of the loop.
    for (final entry in data.entries) {
      try {
        style.updateGeoJsonSource(
          id: _stopSourceId(entry.key),
          data: entry.value,
        );
      } catch (_) {
        // Source momentarily absent (mid style reload) — the next push retries.
      }
    }
  }

  /// Rebuilds the cluster/per-type marker feature lists from [_stops.area] using
  /// the current camera. Client-side screen-space grid clustering (the maplibre
  /// 0.3.x GeoJsonSource has no native clustering).
  void _rebuildMarkerFeatures() {
    final controller = _controller;
    final m = StopMarkers.build(
      stops: _stops.area,
      favoriteIds: _favoriteIds,
      zoom: controller?.getCamera().zoom ?? 14,
      individualZoom: _individualZoom,
      toScreen: controller == null
          ? null
          : (lat, lon) =>
                controller.toScreenLocation(Geographic(lon: lon, lat: lat)),
    );
    _stops.clusterPts = m.clusters;
    _stops.busPts = m.bus;
    _stops.tramPts = m.tram;
    _stops.trolleyPts = m.trolley;
    _stops.mixedPts = m.mixed;
    _pushStopSources();
  }

  Set<String> get _favoriteIds =>
      (ref.read(favoriteStopLocationsProvider).valueOrNull ?? const <Stop>[])
          .map((s) => s.stopId)
          .toSet();
}
