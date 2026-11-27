part of '../home_map_screen.dart';

extension _MapJams on _HomeMapScreenState {
  // ---- Tram-jams: overlay, jam mode and the button --------------------------

  /// Turn a jam board into the amber segment polylines + affected-stop glow points
  /// + the badged-vehicle set, then reconcile the map layers and run the pulse.
  /// Each jam's direction shape (cached) gives both the polyline to project onto
  /// and the affected stops' coords. Geometry gate: a gated (off-shape) jam draws
  /// NO segment (wrong-street risk) — but its stops STILL glow (the glow is the
  /// primary visual, not a fallback) and its vehicles are badged. Best-effort.
  Future<void> _onJamsUpdated(JamsBoard board) async {
    if (_jam.processing) return;
    _jam.processing = true;
    try {
      final shapes = <String, JamShape?>{};
      for (final jam in board.activeJams) {
        final dir = jam.directionRouteId;
        if (dir != null && !shapes.containsKey(dir)) {
          shapes[dir] = await _jamShape(dir);
        }
      }
      if (!mounted) return;
      final next = JamOverlay.build(board.activeJams, shapes)
        ..continuePulseFrom(_jam.overlay);
      _jam.overlay = next;
      await _syncJamLayers();
      _updateJamPulse(active: next.isVisible);
      _reconcileCoverageLayer(); // dim coverage under jam mode (2c)
      _paintVehicles(); // refresh the badge state on the markers
      if (mounted) _setState(() {}); // jam-mode button visibility/count
    } finally {
      _jam.processing = false;
    }
  }

  Future<JamShape?> _jamShape(String directionRouteId) async {
    final cached = _jam.shapeCache[directionRouteId];
    if (cached != null) return cached;
    if (_jam.shapeCache.containsKey(directionRouteId)) return null;
    try {
      final shape = await ref
          .read(linesRepositoryProvider)
          .getShapeByRouteId(directionRouteId);
      final rec = (
        path: RoutePath.fromLatLon(shape.polyline),
        stops: {for (final s in shape.stops) s.stopId: ll.LatLng(s.lat, s.lon)},
      );
      _jam.shapeCache[directionRouteId] = rec;
      return rec;
    } catch (_) {
      _jam.shapeCache[directionRouteId] = null;
      return null;
    }
  }

  /// The pulse: a cheap opacity breath (0.5↔1.0, ~1.75s) driven by a timer that
  /// runs ONLY while a jam is on screen — an empty map spins nothing (thermal).
  void _updateJamPulse({required bool active}) {
    if (active) {
      _jam.pulseTimer ??= Timer.periodic(JamOverlay.pulseTick, (_) {
        _jam.overlay.advancePulse();
        _repushJamOpacity();
      });
    } else {
      _jam.pulseTimer?.cancel();
      _jam.pulseTimer = null;
    }
  }

  void _repushJamOpacity() {
    final style = _style;
    if (style == null || !_jam.layersAdded) return;
    // Only the tiny feature collections are re-pushed (a few features carrying an
    // opacity number) — not a geometry rebuild. line-opacity/circle-opacity read
    // the per-feature `opacity` via a data expression.
    style.updateGeoJsonSource(
      id: _stopSourceId(_LayerIds.jamSegment),
      data: _jam.overlay.segmentsGeoJson(),
    );
    style.updateGeoJsonSource(
      id: _stopSourceId(_LayerIds.jamGlow),
      data: _jam.overlay.glowGeoJson(),
    );
  }

  /// (Re)build the amber segment + stop-glow layers imperatively, inserted BELOW
  /// the stop pins (so pins sit on top) but above the route line.
  Future<void> _syncJamLayers() async {
    final style = _style;
    if (style == null) return;
    final hasAnything = _jam.overlay.isVisible;
    if (!hasAnything) {
      if (_jam.layersAdded) {
        for (final id in const [_LayerIds.jamSegment, _LayerIds.jamGlow]) {
          try {
            await style.removeLayer(id);
          } catch (_) {}
          try {
            await style.removeSource(_stopSourceId(id));
          } catch (_) {}
        }
        _jam.layersAdded = false;
      }
      return;
    }
    // Under the stop pins (bus pin is the lowest pin layer) when present, else
    // just under the vehicle symbols.
    final below = _stops.layersAdded
        ? _LayerIds.bus
        : focusInsertBelowLayerId(vehicleLayersAdded: _vehLayerAdded);
    // Read the theme before the first await: the screen may be gone after it.
    final jamHex = StizeColors.of(context).jam.toHexString();
    try {
      if (!_jam.layersAdded) {
        // Glow first (lowest), then the segment on top of it.
        await style.addSource(
          GeoJsonSource(
            id: _stopSourceId(_LayerIds.jamGlow),
            data: _jam.overlay.glowGeoJson(),
          ),
        );
        await style.addLayer(
          CircleStyleLayer(
            id: _LayerIds.jamGlow,
            sourceId: _stopSourceId(_LayerIds.jamGlow),
            paint: {
              'circle-color': jamHex,
              'circle-radius': 13.0,
              'circle-blur': 0.9,
              'circle-opacity': ['get', 'opacity'],
            },
          ),
          belowLayerId: below,
        );
        await style.addSource(
          GeoJsonSource(
            id: _stopSourceId(_LayerIds.jamSegment),
            data: _jam.overlay.segmentsGeoJson(),
          ),
        );
        await style.addLayer(
          LineStyleLayer(
            id: _LayerIds.jamSegment,
            sourceId: _stopSourceId(_LayerIds.jamSegment),
            layout: {'line-cap': 'round', 'line-join': 'round'},
            paint: {
              'line-color': jamHex,
              'line-width': 4.0, // thinner than the route line (5)
              'line-opacity': ['get', 'opacity'],
            },
          ),
          belowLayerId: below,
        );
        _jam.layersAdded = true;
      } else {
        await style.updateGeoJsonSource(
          id: _stopSourceId(_LayerIds.jamGlow),
          data: _jam.overlay.glowGeoJson(),
        );
        await style.updateGeoJsonSource(
          id: _stopSourceId(_LayerIds.jamSegment),
          data: _jam.overlay.segmentsGeoJson(),
        );
      }
    } catch (_) {
      _jam.layersAdded = false;
    }
  }

  /// The jam-mode toggle button. Present only when the city has active jams; a
  /// toggle (not a screen): on = camera fits all active jams, off = normal view.
  ///
  /// It only NAGS (loud amber icon + red count badge) when at least one jam is
  /// relevant to the user's context — near them, on the followed vehicle's line,
  /// or at the open stop. Jams elsewhere keep the button present but QUIET (muted,
  /// no badge). No jams → no button. The count badge shows the relevant count.
  Widget _jamModeButton() {
    if (!ref.watch(jamDetectionEnabledProvider)) return const SizedBox.shrink();
    final board = ref.watch(jamsProvider).valueOrNull;
    final jams = board?.activeJams ?? const <Jam>[];
    if (jams.isEmpty) {
      // Falling out of jam mode when the last jam clears.
      if (_jam.modeOn) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _setJamMode(false));
      }
      return const SizedBox.shrink();
    }
    final followedLine = _selectedVehicleKey == null
        ? null
        : _vehAnimator.trackFor(_selectedVehicleKey!)?.line;
    final openStopId = _slotStopId ?? _stopContextId;
    final relevant = jams
        .where(
          (j) => isJamRelevant(
            j,
            followedLine: followedLine,
            openStopId: openStopId,
            userLocation: _meTo,
          ),
        )
        .length;
    return JamModeButton(
      on: _jam.modeOn,
      relevantCount: relevant,
      onToggle: () => _setJamMode(!_jam.modeOn),
    );
  }

  /// Whether an active jam lies ahead of the followed vehicle on its own
  /// direction. Uses the track's along-track position + its direction shape, so a
  /// vehicle on the opposite direction or already past the jam gets no warning.
  bool _jamAheadForFollowed(VehicleTrack? track) {
    if (!ref.watch(jamDetectionEnabledProvider)) return false;
    if (track == null || track.path == null) return false;
    final board = ref.watch(jamsProvider).valueOrNull;
    if (board == null) return false;
    for (final jam in board.activeJams) {
      if (isJamAhead(
        jam: jam,
        vehicleDirectionRouteId: track.directionRouteId,
        path: track.path,
        vehicleAlong: track.toDist,
      )) {
        return true;
      }
    }
    return false;
  }

  void _setJamMode(bool on) {
    if (_jam.modeOn == on) return;
    _setState(() => _jam.modeOn = on);
    _reconcileCoverageLayer(); // hide/restore the coverage backdrop (2c)
    if (on) _fitToJams();
  }

  /// Fit the camera to the bounds of every active jam (its vehicles + segment
  /// stops). A jam-mode toggle of the SAME map — no navigation, no back button.
  void _fitToJams() {
    final board = ref.read(jamsProvider).valueOrNull;
    final controller = _controller;
    if (board == null || controller == null) return;
    final pts = <ll.LatLng>[];
    for (final j in board.activeJams) {
      for (final v in j.vehicles) {
        pts.add(v.position);
      }
      if (j.segmentRear != null) pts.add(j.segmentRear!);
      if (j.segmentFront != null) pts.add(j.segmentFront!);
    }
    _fitToPoints(pts);
  }

  /// Fit the camera to [pts] (with a little margin), inside the visible map
  /// area left by the sheet / panel.
  void _fitToPoints(List<ll.LatLng> pts) {
    final controller = _controller;
    if (controller == null) return;
    if (pts.isEmpty) return;
    var minLat = pts.first.latitude, maxLat = pts.first.latitude;
    var minLon = pts.first.longitude, maxLon = pts.first.longitude;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLon = math.min(minLon, p.longitude);
      maxLon = math.max(maxLon, p.longitude);
    }
    // A little padding around the bounds so pins/segment aren't flush to the edge.
    const pad = 0.004;
    _selfMove(() {
      controller.fitBounds(
        bounds: LngLatBounds(
          longitudeWest: minLon - pad,
          latitudeSouth: minLat - pad,
          longitudeEast: maxLon + pad,
          latitudeNorth: maxLat + pad,
        ),
        nativeDuration: StizeMotion.camera,
        padding: _mapInsets,
      );
    });
  }
}
