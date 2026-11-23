part of '../home_map_screen.dart';

extension _MapJams on _HomeMapScreenState {
  // ---- Tram-jam overlay -----------------------------------------------------

  /// Turn a jam board into the amber segment polylines + affected-stop glow points
  /// + the badged-vehicle set, then reconcile the map layers and run the pulse.
  /// Each jam's direction shape (cached) gives both the polyline to project onto
  /// and the affected stops' coords. Geometry gate: a gated (off-shape) jam draws
  /// NO segment (wrong-street risk) — but its stops STILL glow (the glow is the
  /// primary visual, not a fallback) and its vehicles are badged. Best-effort.
  Future<void> _onJamsUpdated(JamsBoard board) async {
    if (_jamsProcessing) return;
    _jamsProcessing = true;
    try {
      final segments = <List<ll.LatLng>>[];
      final glow = <ll.LatLng>[];
      final jammed = <String>{};
      for (final jam in board.activeJams) {
        final dir = jam.directionRouteId;
        final shape = dir == null ? null : await _jamShape(dir);
        final seg = buildJamSegment(jam, shape?.path);
        if (seg.polyline != null) {
          segments.add(seg.polyline!);
        } else {
          for (final v in jam.vehicles) {
            jammed.add(v.garageNo);
          }
        }
        // Glow every affected stop we can resolve from the direction shape.
        if (shape != null) {
          for (final id in jam.affectedStopIds) {
            final c = shape.stops[id];
            if (c != null) glow.add(c);
          }
        }
      }
      if (!mounted) return;
      _jamSegments = segments;
      _jamGlowStops = glow;
      _jammedGarages = jammed;
      await _syncJamLayers();
      _updateJamPulse(active: segments.isNotEmpty || glow.isNotEmpty);
      _reconcileCoverageLayer(); // dim coverage under jam mode (2c)
      _paintVehicles(); // refresh the badge state on the markers
      if (mounted) _setState(() {}); // jam-mode button visibility/count
    } finally {
      _jamsProcessing = false;
    }
  }

  Future<({RoutePath? path, Map<String, ll.LatLng> stops})?> _jamShape(
    String directionRouteId,
  ) async {
    final cached = _jamShapeCache[directionRouteId];
    if (cached != null) return cached;
    if (_jamShapeCache.containsKey(directionRouteId)) return null;
    try {
      final shape = await ref
          .read(linesRepositoryProvider)
          .getShapeByRouteId(directionRouteId);
      final rec = (
        path: RoutePath.fromLatLon(shape.polyline),
        stops: {for (final s in shape.stops) s.stopId: ll.LatLng(s.lat, s.lon)},
      );
      _jamShapeCache[directionRouteId] = rec;
      return rec;
    } catch (_) {
      _jamShapeCache[directionRouteId] = null;
      return null;
    }
  }

  /// The pulse: a cheap opacity breath (0.5↔1.0, ~1.75s) driven by a timer that
  /// runs ONLY while a jam is on screen — an empty map spins nothing (thermal).
  void _updateJamPulse({required bool active}) {
    if (active) {
      _jamPulseTimer ??= Timer.periodic(const Duration(milliseconds: 90), (_) {
        _jamPulsePhase =
            (_jamPulsePhase + (2 * math.pi * 0.09 / 1.75)) % (2 * math.pi);
        _repushJamOpacity();
      });
    } else {
      _jamPulseTimer?.cancel();
      _jamPulseTimer = null;
    }
  }

  double get _jamPulseOpacity =>
      0.5 + 0.5 * (0.5 + 0.5 * math.sin(_jamPulsePhase));

  void _repushJamOpacity() {
    final style = _style;
    if (style == null || !_jamLayersAdded) return;
    // Only the tiny feature collections are re-pushed (a few features carrying an
    // opacity number) — not a geometry rebuild. line-opacity/circle-opacity read
    // the per-feature `opacity` via a data expression.
    style.updateGeoJsonSource(
      id: _stopSourceId(_HomeMapScreenState._jamSegmentLayerId),
      data: _jamSegmentsGeoJson(),
    );
    style.updateGeoJsonSource(
      id: _stopSourceId(_HomeMapScreenState._jamGlowLayerId),
      data: _jamGlowGeoJson(),
    );
  }

  /// (Re)build the amber segment + stop-glow layers imperatively, inserted BELOW
  /// the stop pins (so pins sit on top) but above the route line.
  Future<void> _syncJamLayers() async {
    final style = _style;
    if (style == null) return;
    final hasAnything = _jamSegments.isNotEmpty || _jamGlowStops.isNotEmpty;
    if (!hasAnything) {
      if (_jamLayersAdded) {
        for (final id in const [
          _HomeMapScreenState._jamSegmentLayerId,
          _HomeMapScreenState._jamGlowLayerId,
        ]) {
          try {
            await style.removeLayer(id);
          } catch (_) {}
          try {
            await style.removeSource(_stopSourceId(id));
          } catch (_) {}
        }
        _jamLayersAdded = false;
      }
      return;
    }
    // Under the stop pins (bus pin is the lowest pin layer) when present, else
    // just under the vehicle symbols.
    final below = _stopLayersAdded
        ? _HomeMapScreenState._busLayerId
        : focusInsertBelowLayerId(vehicleLayersAdded: _vehLayerAdded);
    try {
      if (!_jamLayersAdded) {
        // Glow first (lowest), then the segment on top of it.
        await style.addSource(
          GeoJsonSource(
            id: _stopSourceId(_HomeMapScreenState._jamGlowLayerId),
            data: _jamGlowGeoJson(),
          ),
        );
        await style.addLayer(
          CircleStyleLayer(
            id: _HomeMapScreenState._jamGlowLayerId,
            sourceId: _stopSourceId(_HomeMapScreenState._jamGlowLayerId),
            paint: {
              'circle-color': StizeColors.of(context).jam.toHexString(),
              'circle-radius': 13.0,
              'circle-blur': 0.9,
              'circle-opacity': ['get', 'opacity'],
            },
          ),
          belowLayerId: below,
        );
        await style.addSource(
          GeoJsonSource(
            id: _stopSourceId(_HomeMapScreenState._jamSegmentLayerId),
            data: _jamSegmentsGeoJson(),
          ),
        );
        await style.addLayer(
          LineStyleLayer(
            id: _HomeMapScreenState._jamSegmentLayerId,
            sourceId: _stopSourceId(_HomeMapScreenState._jamSegmentLayerId),
            layout: {'line-cap': 'round', 'line-join': 'round'},
            paint: {
              'line-color': StizeColors.of(context).jam.toHexString(),
              'line-width': 4.0, // thinner than the route line (5)
              'line-opacity': ['get', 'opacity'],
            },
          ),
          belowLayerId: below,
        );
        _jamLayersAdded = true;
      } else {
        await style.updateGeoJsonSource(
          id: _stopSourceId(_HomeMapScreenState._jamGlowLayerId),
          data: _jamGlowGeoJson(),
        );
        await style.updateGeoJsonSource(
          id: _stopSourceId(_HomeMapScreenState._jamSegmentLayerId),
          data: _jamSegmentsGeoJson(),
        );
      }
    } catch (_) {
      _jamLayersAdded = false;
    }
  }

  String _jamSegmentsGeoJson() {
    final o = _jamSegments.isEmpty ? 0.0 : _jamPulseOpacity;
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        for (final seg in _jamSegments)
          {
            'type': 'Feature',
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                for (final p in seg) [p.longitude, p.latitude],
              ],
            },
            'properties': {'opacity': o},
          },
      ],
    });
  }

  String _jamGlowGeoJson() {
    // The glow breathes a touch softer than the line.
    final o = _jamGlowStops.isEmpty ? 0.0 : (_jamPulseOpacity * 0.55);
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        for (final p in _jamGlowStops)
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [p.longitude, p.latitude],
            },
            'properties': {'opacity': o},
          },
      ],
    });
  }

  Widget _searchResultsList(AppLocalizations l10n) {
    final hasResults =
        _resultStops.isNotEmpty ||
        _resultLines.isNotEmpty ||
        _resultPlaces.isNotEmpty;
    if (!hasResults) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(l10n.searchNoResults, textAlign: TextAlign.center),
      );
    }
    return ListView(
      shrinkWrap: true,
      children: [
        for (final stop in _resultStops)
          ListTile(
            leading: const Icon(StizeIcons.pin),
            title: Text(stop.name),
            subtitle: Text(stop.lines.join(', ')),
            onTap: () => _openStop(stop, source: Ev.srcSearch),
          ),
        for (final line in _resultLines)
          ListTile(
            leading: vehicleGlyph(
              line.vehicleType,
              size: 24,
              color: vehicleColor(line.vehicleType),
            ),
            title: Text(line.line),
            subtitle: Text('${line.origin} → ${line.destination}'),
            trailing: IconButton(
              icon: Icon(
                _isLinePinned(line.line)
                    ? StizeIcons.pinPushFilled
                    : StizeIcons.pinPush,
              ),
              tooltip: l10n.pinLineTooltip,
              onPressed: () => _togglePinLine(line),
            ),
            onTap: () => _openLine(line),
          ),
        for (final place in _resultPlaces)
          ListTile(
            leading: const Icon(StizeIcons.map),
            title: Text(place.displayName),
            onTap: () => _openPlace(place),
          ),
      ],
    );
  }
}
