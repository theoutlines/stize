part of '../home_map_screen.dart';

extension _MapLayers on _HomeMapScreenState {
  // ---- Vehicle-layer driver (runs only while something is actually moving) --

  /// Start driving the vehicle layer's repaints.
  ///
  /// **Timed mode** uses a per-frame (vsync) [Ticker] so continuous plan-driven
  /// motion is smooth (~60fps). **Conservative mode** keeps the coarse 66ms
  /// sampler: the marker only inches toward its last fix, 15fps is plenty, and it
  /// keeps prod off a 60fps loop. Either way the driver stops the instant nothing
  /// is moving (idle = zero frames), for both render paths.
  void _startVehDriver() {
    _vehTicker ??= createTicker((_) => _pumpVehLayer());
    if (!_vehTicker!.isActive) _vehTicker!.start();
  }

  // One repaint step: advance any timed players by wall-clock, then either paint
  // the current positions (while motion continues) or, when nothing is moving,
  // stop the driver and settle on the final frame.
  void _pumpVehLayer() {
    _vehAnimator.advanceTimed(DateTime.now());
    _diag.pumpCount++;
    // Keep ticking while a fan is still easing into place even if nothing is
    // "playing" (choral HOLD): _paintVehicles → _arrangeVehicles advances the
    // ease and clears fanAnimating once it settles.
    if (_vehAnim.isAnimating ||
        _vehAnimator.hasPendingMotion ||
        _vehArranger.fanAnimating) {
      _paintVehicles();
      _refreshFollowPanel();
    } else {
      _stopVehDriver();
      _paintVehicles();
      if (mounted) _setState(() {});
    }
  }

  void _refreshFollowPanel() {
    if (!_panelActive || _selectedVehicleKey == null || _slotModel != null)
      return;
    final now = DateTime.now();
    final last = _follow.lastPanelRefreshAt;
    if (last != null && now.difference(last) < const Duration(seconds: 1))
      return;
    _follow.lastPanelRefreshAt = now;
    if (mounted) _setState(() {});
  }

  /// Push the current vehicle positions to the GPU symbol source.
  void _paintVehicles() {
    _writeVehiclesToSource();
  }

  void _stopVehDriver() {
    _vehTicker?.stop(); // keep the Ticker instance; dispose only in dispose()
  }

  void _onVehAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      // The 30s ease controller finished. In timed mode the driver must keep
      // running while a plan is still playing, so only stop it when nothing is
      // moving; otherwise leave it to self-stop when the plan is exhausted.
      if (!_vehAnimator.hasPendingMotion) _stopVehDriver();
      // One final paint so the layer lands on the settled positions and the
      // markers' halos drop out of their breathing state (animate == false).
      _paintVehicles();
      if (mounted) _setState(() {});
    }
  }

  // ---- Map lifecycle --------------------------------------------------------

  void _onMapCreated(MapController controller) {
    _controller = controller;
    // Apply any camera target that resolved before the map was ready — through
    // the geometry-aware helper so the initial centre respects the panel/sheet.
    if (_pendingCenter != null) {
      _camMove(center: _pendingCenter!, zoom: _pendingZoom ?? 16);
      _pendingCenter = null;
      _pendingZoom = null;
    }
  }

  Future<void> _onStyleLoaded(StyleController style) async {
    _style = style;
    // A fresh style (first load or after a theme flip) has none of our layers;
    // the stop layers, heatmap and vehicle symbol layers must be (re)added.
    _cov.added = false;
    _stops.layersAdded = false;
    _vehLayerAdded = false;
    _focusLayersAdded = false;
    await registerStigmaImages(style, _scheme, owner: this);
    if (!mounted) return;
    // Stops FIRST so they sit *under* the vehicle symbols added next — moving
    // objects belong above the stop/rail infrastructure (C2). Rails are the
    // lowest of the stop layers (see _addStopLayers).
    await _addStopLayers(style);
    await registerMovingObjectImages(style, owner: this);
    await _addVehicleSymbolLayers();
    if (!mounted) return;
    _setState(() => _imagesReady = true);
    // Show stops and live vehicles for wherever the map currently sits, even
    // before a location fix — transport shows up right away. Re-push any data
    // already in hand (e.g. tram rails, area stops) onto the fresh sources.
    _pushStopSources();
    // Re-add the focused-line layers (below the vehicle symbols) if a line is
    // focused across this style (re)load — e.g. a theme flip mid-follow.
    if (_focus != null) _syncFocusLayers();
    _browse.dotAdded = false;
    _pushBrowseDot();
    _loadStopsForVisibleArea();
    _loadVehiclesForVisibleArea(force: true);
    // Rails + the line-type index are decoration, not the first answer: load
    // them once, a moment after the map and the nearby list are up, so their
    // 12 fetches and the layer rebuilds don't stutter the opening animation
    // (owner, mobile, 2026-11-22). A style reload reuses what's already in hand.
    if (_stops.rails.isEmpty) {
      _stops.railsTimer?.cancel();
      _stops.railsTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _loadTramRails();
      });
    }
    _reconcileCoverageLayer();
  }

  /// Adds the moving-object GeoJSON source and its three symbol layers (badge,
  /// direction arrow, coin label). Idempotent per style load. On any failure it
  /// degrades quietly: the flag is left un-added so a later reconcile can retry,
  /// and the map simply shows no vehicle symbols rather than crashing.
  Future<void> _addVehicleSymbolLayers() async {
    final style = _style;
    if (style == null || _vehLayerAdded || _vehLayerAdding) return;
    _vehLayerAdding = true;
    try {
      // Vehicle symbols sit above the stop/rail layers (added earlier in
      // _onStyleLoaded). Tram rails are handled by the imperative stop layers
      // (stg-stops-rails) in both modes, not here.
      await style.addSource(movingObjectsSource());
      await style.addLayer(movingObjectsBadgeLayer());
      await style.addLayer(movingObjectsArrowLayer());
      await style.addLayer(movingObjectsLabelLayer());
      // Flip the "added" flag only now that the badge really exists, so a focus
      // that lands mid-add doesn't ask to insert *below a badge that isn't there
      // yet* (belowLayerId → maplibre throws → the route silently vanishes). Until
      // then focusInsertBelowLayerId returns null and the route goes on top
      // (visible), then the re-sync below drops it under the badge.
      _vehLayerAdded = true;
      // Paint whatever the animator already holds, so vehicles show at once
      // (also covers a theme-flip re-add).
      _writeVehiclesToSource();
      // If a line was focused before the vehicle layers came up, re-place its
      // route now that there's a badge to sit under.
      if (_focus != null) _syncFocusLayers();
    } catch (_) {
      _vehLayerAdded = false;
    } finally {
      _vehLayerAdding = false;
    }
  }

  /// Builds the typed moving-object set from the animator's current positions
  /// and pushes it to the GPU symbol source. Applies spiderfy (coincident
  /// vehicles fanned out) and the selected/focus state. No fleet id / identity
  /// is written — only what the layer draws and a tap needs to route.
  void _writeVehiclesToSource() {
    final style = _style;
    if (style == null || !_vehLayerAdded) return;
    final t = _vehAnim.value;
    final focusLine = _focus?.line;
    final objects = <MovingObject>[];
    for (final entry in _vehAnimator.currentPositions(t)) {
      final track = _vehAnimator.trackFor(entry.key);
      if (track == null) continue;
      if (focusLine != null && track.line != focusLine) continue;
      final scheduled = track.source == VehicleSource.scheduled;
      objects.add(
        MovingObject(
          key: entry.key,
          position: entry.value,
          kind: MovingObjectKind.fromVehicleType(track.type),
          label: track.line,
          heading: _vehAnimator.headingAt(entry.key, t),
          selected: entry.key == _selectedVehicleKey,
          // Crimson "stuck" visual doubles as the jam badge for a jam whose red
          // segment was geometry-gated (off-shape line). This reuses the VISUAL,
          // not the animator's stuck SIGNAL — the jam state comes from /jams. The
          // track key is the garage number for a real vehicle.
          stuck:
              _vehAnimator.isStuck(entry.key) ||
              _jam.jammedGarages.contains(entry.key),
          // Fade a vanishing/stale vehicle over its grace period (X6), and dim a
          // schedule-predicted object so it reads as "by schedule, not live".
          opacity:
              _vehAnimator.opacityFor(entry.key) *
              (scheduled ? kScheduledBaseOpacity : 1.0),
          moving: _vehAnimator.hasMotion(entry.key),
          source: track.source,
        ),
      );
    }
    final zoom = _controller?.getCamera().zoom ?? 15.0;
    final placed = _arrangeVehicles(objects, zoom);
    // Draw scheduled objects first (underneath) so a live vehicle always sits on
    // top where the two overlap — live is the authoritative position.
    placed.sort((a, b) {
      final av = a.source == VehicleSource.scheduled ? 0 : 1;
      final bv = b.source == VehicleSource.scheduled ? 0 : 1;
      return av.compareTo(bv);
    });
    style.updateGeoJsonSource(
      id: movingObjectsSourceId,
      data: movingObjectsGeoJson(placed),
    );
    // Follow mode: keep the selected vehicle in view as its marker moves. Runs
    // on the same cadence as the layer repaint so the camera tracks smoothly.
    if (_follow.active) _followTick();
  }

  /// Arranges the vehicles through [_vehArranger] (fan at stops, dim when
  /// crossing) and keeps the frame driver alive while a fan is still easing.
  List<MovingObject> _arrangeVehicles(List<MovingObject> objects, double zoom) {
    final driverRunning = _vehTicker?.isActive ?? false;
    final placed = _vehArranger.arrange(
      objects,
      zoom,
      driverRunning: driverRunning,
      refLatitude: _belgradeCenter.lat,
    );
    if (_vehArranger.fanAnimating && !driverRunning && !_paused) {
      _startVehDriver();
    }
    return placed;
  }

  /// Adds the coverage heatmap source + layer the first time the map is zoomed
  /// out past the threshold (and re-adds it after a theme flip while it's
  /// visible). The layer is never removed once added — its zoom-driven opacity
  /// hides it when zoomed in — so this only ever mounts, guarded by hysteresis
  /// so a zoom hovering at the threshold doesn't churn. No-op when the flag is
  /// off or the style/controller isn't ready yet.
  Future<void> _reconcileCoverageLayer() async {
    final style = _style;
    final controller = _controller;
    if (style == null || controller == null) return;
    // Jam mode: the event matters more than the ambient density backdrop, so hide
    // the coverage heatmap while it's on (2c). Restored when jam mode turns off.
    if (_jam.modeOn) {
      if (_cov.added) {
        try {
          await style.removeLayer(coverageMainLayerId);
        } catch (_) {}
        try {
          await style.removeSource(coverageSourceId);
        } catch (_) {}
        _cov.added = false;
        _cov.active = false;
      }
      return;
    }
    if (!_cov.enabled) return;
    final zoom = controller.getCamera().zoom;
    _cov.active = coverageMainHeatmapActive(zoom: zoom, wasActive: _cov.active);
    if (!_cov.active || _cov.added) return;
    // Claim the slot before the first await so a burst of idle events can't
    // race two adds of the same source/layer.
    _cov.added = true;
    final dark = Theme.of(context).brightness == Brightness.dark;
    try {
      await style.addSource(coverageSource());
      await style.addLayer(coverageMainLayer(dark: dark));
    } catch (_) {
      // Failed (e.g. style torn down mid-add) — allow a later retry.
      _cov.added = false;
    }
  }

  /// Fetches the tram lines' route shapes once and keeps them as thin rail
  /// lines on the map (C2). Best-effort per line — a missing shape just omits
  /// that route.
  Future<void> _loadTramRails() async {
    if (_stops.railsRequested) return;
    _stops.railsRequested = true;
    final repo = ref.read(linesRepositoryProvider);
    // Install the authoritative line→type index (feed route_type) once. It
    // drives the tram-rail set below (only tram lines the bundle actually
    // carries — so no 404 on absent numbers 3/7/9) and is the fallback type
    // source for any stop whose bundle predates per-stop `types`.
    try {
      final allLines = await repo.getAll();
      if (allLines.isNotEmpty) {
        setLineTypeIndex(LineTypeIndex.fromLines(allLines));
        _pushStopSources(); // re-evaluate stop markers now types can resolve
      }
    } catch (_) {
      // Offline with no cache yet: rails stay empty this run, self-heal later.
    }
    final rails = <List<List<double>>>[];
    await Future.wait([
      for (final line in tramLineNumbers)
        repo
            .getShapeByLineNumber(line)
            .then((shape) {
              if (shape.polyline.length >= 2) rails.add(shape.polyline);
            })
            .catchError((_) {}),
    ]);
    if (!mounted) return;
    _stops.rails = rails;
    // Rails are one of the imperative stop layers (stg-stops-rails), rendered the
    // same way in both symbol and widget modes — push the fresh geometry onto it.
    _pushStopSources();
  }

  void _onEvent(MapEvent event) {
    if (event is MapEventCameraIdle) {
      // While following, the camera is being panned every frame by us — don't
      // treat those idles as browsing (they'd hammer the stop/vehicle reload).
      if (_follow.active) return;
      _onBrowseIdle();
      _loadStopsForVisibleArea();
      _loadVehiclesForVisibleArea();
      _reconcileCoverageLayer();
    } else if (event is MapEventMoveCamera) {
      // The lifted dot rides the visible centre while the map moves.
      if (_browse.lifted) _pushBrowseDot();
    } else if (event is MapEventClick) {
      _handleTap(event.point);
    } else if (event is MapEventStartMoveCamera) {
      // A camera event in the brief post-resume window is the tab-return canvas
      // re-layout, not a user gesture — never break follow on it.
      final guard = _follow.resumeGuardUntil;
      if (guard != null && DateTime.now().isBefore(guard)) return;
      if (!_selfCameraMove && event.reason == CameraChangeReason.apiGesture) {
        _onBrowseDragStart();
      }
      // Break follow only on a genuine user pan/zoom (the marker + highlight
      // stay). Our own programmatic pans are bracketed by [_selfCameraMove] so
      // they never count — even if the platform mislabels one as a gesture — so
      // the per-frame follow pan can't cancel its own follow.
      if (shouldBreakFollow(
        following: _follow.active,
        selfMove: _selfCameraMove,
        reason: event.reason,
      )) {
        _stopFollow();
        // Surface the "Back to vehicle" pill (decision #8): the user panned the
        // vehicle away, so follow is now interrupted while the context stays up.
        if (_panelActive && mounted) _setState(() {});
      }
    }
  }
}
