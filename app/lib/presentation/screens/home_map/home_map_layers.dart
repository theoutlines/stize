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
    _pumpCount++;
    // Keep ticking while a fan is still easing into place even if nothing is
    // "playing" (choral HOLD): _paintVehicles → _arrangeVehicles advances the
    // ease and clears _fanAnimating once it settles.
    if (_vehAnim.isAnimating ||
        _vehAnimator.hasPendingMotion ||
        _fanAnimating) {
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
    final last = _lastFollowPanelRefreshAt;
    if (last != null && now.difference(last) < const Duration(seconds: 1))
      return;
    _lastFollowPanelRefreshAt = now;
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
    _coverageAdded = false;
    _stopLayersAdded = false;
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
    _loadStopsForVisibleArea();
    _loadVehiclesForVisibleArea(force: true);
    // Rails + the line-type index are decoration, not the first answer: load
    // them once, a moment after the map and the nearby list are up, so their
    // 12 fetches and the layer rebuilds don't stutter the opening animation
    // (owner, mobile, 2026-11-22). A style reload reuses what's already in hand.
    if (_tramRails.isEmpty) {
      _railsTimer?.cancel();
      _railsTimer = Timer(const Duration(seconds: 2), () {
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
              _jammedGarages.contains(entry.key),
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
    if (_following) _followTick();
  }

  /// Arranges the vehicle set for the symbol source with two distinct behaviours,
  /// per the owner's brief:
  ///
  ///  * **Stationary coincident vehicles are fanned out** (several at a stop /
  ///    terminus read as several, F4). Their positions don't move, so the fan is
  ///    stable — no hold/debounce needed.
  ///  * **Moving vehicles are never displaced.** Two that cross (oncoming lanes,
  ///    an intersection) simply **pass over each other**; the one(s) overlapping
  ///    fade slightly so the overlap reads as two, not one. No sideways jumps.
  ///
  /// Position offsets (stationary fan) and crossing opacity are both eased while a
  /// driver produces frames and snapped on a one-off write at rest, so nothing is
  /// left half-arranged and idle stays at zero frames.
  List<MovingObject> _arrangeVehicles(List<MovingObject> objects, double zoom) {
    // Far zoom shows plain dots (below the detail threshold): don't fan or
    // cross-fade there. The cell grid is coarse in metres when zoomed out, so
    // membership churns as the camera moves — that churn read as jitter on the
    // overview. Dots overlapping is fine; render true positions, state cleared.
    if (objects.isEmpty || zoom < kMovingObjectDetailZoom) {
      _spiderfyOffset.clear();
      _crossOpacity.clear();
      return objects;
    }
    final metersPerPixel =
        156543.03392 *
        math.cos(_belgradeCenter.lat * math.pi / 180) /
        math.pow(2, zoom);
    final radiusM = 16.0 * metersPerPixel; // fan radius, constant on screen

    // Overlap thresholds, in screen pixels so they mean the same at any zoom —
    // and hysteretic. With one threshold, a pair sitting right at it fans out,
    // collapses, fans out again. So a fan only *forms* on a strong overlap
    // ([enterM], markers clearly on top of each other) and only *collapses*
    // once they are comfortably apart ([exitM]); in between, whatever the fan is
    // already doing wins.
    final enterM = 24.0 * metersPerPixel;
    final exitM = 40.0 * metersPerPixel;
    String cellOf(ll.LatLng p, double m) {
      final lat = m / 111320.0;
      final lon = m / (111320.0 * math.cos(p.latitude * math.pi / 180));
      return '${(p.latitude / lat).floor()}:${(p.longitude / lon).floor()}';
    }

    final driverRunning = _vehTicker?.isActive ?? false;

    // --- Pass 1: fan out stationary coincident vehicles ---------------------
    // Consider ONLY the stationary ones, so a moving vehicle passing through a
    // parked cluster's cell can't collapse the fan. `moving` counts a stop dwell
    // as motion (TimedTrajectory.isPlaying): a bus pausing three seconds is
    // mid-journey, and fanning it out on arrival only to snap it back as it
    // pulls away would be a shove at every stop.
    final crowdedEnter = <String, int>{};
    final byExitCell = <String, List<int>>{};
    for (var i = 0; i < objects.length; i++) {
      if (objects[i].moving) continue;
      final p = objects[i].position;
      crowdedEnter.update(cellOf(p, enterM), (v) => v + 1, ifAbsent: () => 1);
      byExitCell.putIfAbsent(cellOf(p, exitM), () => []).add(i);
    }
    final offsetTarget = <String, ll.LatLng>{}; // dLat,dLon per key
    for (final group in byExitCell.values) {
      // Who in this loose group actually earns a fan: anyone strongly overlapped
      // right now, plus anyone already fanned (that's the hysteresis — they hold
      // their place until the whole group thins out).
      final members = [
        for (final i in group)
          if ((crowdedEnter[cellOf(objects[i].position, enterM)] ?? 0) >= 2 ||
              _spiderfyOffset.containsKey(objects[i].key))
            i,
      ];
      if (members.length < 2) continue;
      members.sort((a, b) => objects[a].key.compareTo(objects[b].key));
      for (var r = 0; r < members.length; r++) {
        final o = objects[members[r]];
        final angle = 2 * math.pi * r / members.length;
        offsetTarget[o.key] = ll.LatLng(
          radiusM * math.sin(angle) / 111320.0,
          radiusM *
              math.cos(angle) /
              (111320.0 * math.cos(o.position.latitude * math.pi / 180)),
        );
      }
    }

    // Is the fan still in transit — any key's offset not yet at its target?
    // (Forming, dissolving, or re-fanning.) If so while the driver is stopped —
    // a choral HOLD parks every marker, so nothing is "playing" to keep it alive
    // — kick the driver so the offsets EASE instead of snapping (a sideways shove
    // reads as a glitch). It self-stops once [_fanAnimating] clears below.
    var changing = false;
    for (final o in objects) {
      final tgt = offsetTarget[o.key] ?? const ll.LatLng(0, 0);
      final cur = _spiderfyOffset[o.key] ?? const ll.LatLng(0, 0);
      if ((tgt.latitude - cur.latitude).abs() > 1e-7 ||
          (tgt.longitude - cur.longitude).abs() > 1e-7) {
        changing = true;
        break;
      }
    }
    _fanAnimating = changing;
    if (changing && !driverRunning && !_paused) _startVehDriver();
    final ease = (driverRunning || changing) ? 0.3 : 1.0;

    // Ease each key's applied offset toward its target (zero if not in a
    // stationary cluster) and compute placed positions.
    final placedPos = <ll.LatLng>[];
    for (final o in objects) {
      final target = offsetTarget[o.key] ?? const ll.LatLng(0, 0);
      final cur = _spiderfyOffset[o.key] ?? const ll.LatLng(0, 0);
      final applied = ll.LatLng(
        cur.latitude + (target.latitude - cur.latitude) * ease,
        cur.longitude + (target.longitude - cur.longitude) * ease,
      );
      if (applied.latitude.abs() < 1e-7 && applied.longitude.abs() < 1e-7) {
        _spiderfyOffset.remove(o.key);
        placedPos.add(o.position);
      } else {
        _spiderfyOffset[o.key] = applied;
        placedPos.add(
          ll.LatLng(
            o.position.latitude + applied.latitude,
            o.position.longitude + applied.longitude,
          ),
        );
      }
    }

    // --- Pass 2: cross-fade moving vehicles that overlap --------------------
    // Count occupancy of each cell at the placed positions; a MOVING vehicle
    // sharing a cell with anything else is "crossing" and dims a little. Its own
    // threshold (~a marker's width): the fan's enter/exit pair above is about
    // whether to *move* a marker, which needs the hysteresis; a fade is
    // continuous and eased, so a single threshold can't flicker.
    final overlapM = 30.0 * metersPerPixel;
    final cellCount = <String, int>{};
    for (final p in placedPos) {
      cellCount.update(cellOf(p, overlapM), (v) => v + 1, ifAbsent: () => 1);
    }
    const crossOpacity = 0.7;
    final present = <String>{};
    final result = <MovingObject>[];
    for (var i = 0; i < objects.length; i++) {
      final o = objects[i];
      present.add(o.key);
      final crossing =
          o.moving && (cellCount[cellOf(placedPos[i], overlapM)] ?? 0) > 1;
      final targetOpacity = crossing ? crossOpacity : 1.0;
      final curOpacity = _crossOpacity[o.key] ?? 1.0;
      final appliedOpacity = curOpacity + (targetOpacity - curOpacity) * ease;
      if ((appliedOpacity - 1.0).abs() < 0.02) {
        _crossOpacity.remove(o.key);
      } else {
        _crossOpacity[o.key] = appliedOpacity;
      }
      result.add(
        MovingObject(
          key: o.key,
          position: placedPos[i],
          kind: o.kind,
          label: o.label,
          heading: o.heading,
          selected: o.selected,
          stuck: o.stuck,
          // Combine the grace/scheduled fade with the crossing dim.
          opacity: o.opacity * appliedOpacity,
          moving: o.moving,
          source: o.source,
        ),
      );
    }
    _spiderfyOffset.removeWhere((k, _) => !present.contains(k));
    _crossOpacity.removeWhere((k, _) => !present.contains(k));
    return result;
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
    if (_jamModeOn) {
      if (_coverageAdded) {
        try {
          await style.removeLayer(coverageMainLayerId);
        } catch (_) {}
        try {
          await style.removeSource(coverageSourceId);
        } catch (_) {}
        _coverageAdded = false;
        _coverageActive = false;
      }
      return;
    }
    if (!_coverageEnabled) return;
    final zoom = controller.getCamera().zoom;
    _coverageActive = coverageMainHeatmapActive(
      zoom: zoom,
      wasActive: _coverageActive,
    );
    if (!_coverageActive || _coverageAdded) return;
    // Claim the slot before the first await so a burst of idle events can't
    // race two adds of the same source/layer.
    _coverageAdded = true;
    final dark = Theme.of(context).brightness == Brightness.dark;
    try {
      await style.addSource(coverageSource());
      await style.addLayer(coverageMainLayer(dark: dark));
    } catch (_) {
      // Failed (e.g. style torn down mid-add) — allow a later retry.
      _coverageAdded = false;
    }
  }

  /// Fetches the tram lines' route shapes once and keeps them as thin rail
  /// lines on the map (C2). Best-effort per line — a missing shape just omits
  /// that route.
  Future<void> _loadTramRails() async {
    if (_tramRailsRequested) return;
    _tramRailsRequested = true;
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
    _tramRails = rails;
    // Rails are one of the imperative stop layers (stg-stops-rails), rendered the
    // same way in both symbol and widget modes — push the fresh geometry onto it.
    _pushStopSources();
  }

  void _onEvent(MapEvent event) {
    if (event is MapEventCameraIdle) {
      // While following, the camera is being panned every frame by us — don't
      // treat those idles as browsing (they'd hammer the stop/vehicle reload).
      if (_following) return;
      _onBrowseIdle();
      _loadStopsForVisibleArea();
      _loadVehiclesForVisibleArea();
      _reconcileCoverageLayer();
    } else if (event is MapEventClick) {
      _handleTap(event.point);
    } else if (event is MapEventStartMoveCamera) {
      // A camera event in the brief post-resume window is the tab-return canvas
      // re-layout, not a user gesture — never break follow on it.
      final guard = _followResumeGuardUntil;
      if (guard != null && DateTime.now().isBefore(guard)) return;
      if (!_selfCameraMove && event.reason == CameraChangeReason.apiGesture) {
        _onBrowseDragStart();
      }
      // Break follow only on a genuine user pan/zoom (the marker + highlight
      // stay). Our own programmatic pans are bracketed by [_selfCameraMove] so
      // they never count — even if the platform mislabels one as a gesture — so
      // the per-frame follow pan can't cancel its own follow.
      if (shouldBreakFollow(
        following: _following,
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

  // ---- Stops for the visible area ------------------------------------------

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
      if (_areaStops.isNotEmpty) {
        _lastFetchCenter = null;
        _setState(() {
          _areaStops = [];
          _rebuildMarkerFeatures();
        });
      }
      return;
    }
    final center = ll.LatLng(camera.center.lat, camera.center.lon);
    final radius = _radiusForVisibleArea(camera);
    if (_lastFetchCenter != null) {
      final moved = _distance.as(
        ll.LengthUnit.Meter,
        _lastFetchCenter!,
        center,
      );
      if (moved < _lastFetchRadius * 0.35 &&
          (radius - _lastFetchRadius).abs() < _lastFetchRadius * 0.5) {
        // Barely moved — still recluster (zoom may have changed) but skip refetch.
        _setState(_rebuildMarkerFeatures);
        return;
      }
    }
    final seq = ++_stopsRequestSeq;
    _lastFetchCenter = center;
    _lastFetchRadius = radius;
    try {
      final stops = await ref
          .read(stopsRepositoryProvider)
          .nearby(
            lat: center.latitude,
            lon: center.longitude,
            radiusMeters: radius,
          );
      if (!mounted || seq != _stopsRequestSeq) return;
      _setState(() {
        _areaStops = stops;
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
    if (_stopLayersAdded || _stopLayersAdding) return;
    _stopLayersAdding = true;
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
        _HomeMapScreenState._railsLayerId,
        const PolylineLayer(polylines: [], color: tramRailColor, width: 2),
      ),
      (
        _HomeMapScreenState._clusterLayerId,
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
      (_HomeMapScreenState._busLayerId, pin(MapImages.bus)),
      (_HomeMapScreenState._tramLayerId, pin(MapImages.tram)),
      (_HomeMapScreenState._trolleyLayerId, pin(MapImages.trolley)),
      (_HomeMapScreenState._mixedLayerId, pin(MapImages.mixedStop)),
      (_HomeMapScreenState._favLayerId, pin(MapImages.favorite)),
      (
        _HomeMapScreenState._placeLayerId,
        pin(MapImages.place, anchor: IconAnchor.bottom),
      ),
    ];
    try {
      for (final (id, tmpl) in specs) {
        final srcId = _stopSourceId(id);
        await style.addSource(
          GeoJsonSource(
            id: srcId,
            data: _HomeMapScreenState._emptyFeatureCollection,
          ),
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
      _stopLayersAdded = true;
    } catch (_) {
      // Style torn down mid-add (e.g. a theme flip) — allow a later retry.
      _stopLayersAdded = false;
    } finally {
      _stopLayersAdding = false;
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
    if (_stopPushTimer?.isActive ?? false) return;
    _stopPushTimer = Timer(const Duration(milliseconds: 32), () {
      if (mounted) _pushStopSourcesNow();
    });
  }

  void _pushStopSourcesNow() {
    final style = _style;
    if (style == null || !_stopLayersAdded) return;
    // While a line is focused, only its own route shows (via the declarative
    // focus layers) — empty every ambient stop source so nothing else competes.
    // Also hide the stops when the coverage heatmap stands in for them (flag on +
    // zoomed out); the heatmap shows through.
    final focused = _focus != null;
    final zoom = _controller?.getCamera().zoom ?? 15.0;
    final hidden =
        focused || (_coverageEnabled && coverageMainStopsOpacity(zoom) <= 0.01);
    final favStops =
        ref.read(favoriteStopLocationsProvider).valueOrNull ?? const <Stop>[];
    // Serialise via `jsonEncode`, NOT geobase's `FeatureCollection.toText()`:
    // toText() does not escape `"` (and other specials) in string properties, so
    // a stop whose name contains a quote — e.g. `Park "Tašmajdan"` (19 such stops
    // in the feed) — produced invalid JSON, which the web plugin's
    // `setData(JSON.parse(data))` threw on, leaving that source empty and its
    // stops unrendered. `jsonEncode` escapes correctly.
    String pointsFc(List<Feature<Point>> f) {
      if (hidden) return _HomeMapScreenState._emptyFeatureCollection;
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
      _HomeMapScreenState._railsLayerId: focused
          ? _HomeMapScreenState._emptyFeatureCollection
          : jsonEncode({
              'type': 'FeatureCollection',
              'features': [
                for (final poly in _tramRails)
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
      _HomeMapScreenState._clusterLayerId: pointsFc(_clusterPts),
      _HomeMapScreenState._busLayerId: pointsFc(_busPts),
      _HomeMapScreenState._tramLayerId: pointsFc(_tramPts),
      _HomeMapScreenState._trolleyLayerId: pointsFc(_trolleyPts),
      _HomeMapScreenState._mixedLayerId: pointsFc(_mixedPts),
      _HomeMapScreenState._favLayerId: focused
          ? _HomeMapScreenState._emptyFeatureCollection
          : jsonEncode({
              'type': 'FeatureCollection',
              'features': [for (final s in favStops) stopFeature(s)],
            }),
      _HomeMapScreenState._placeLayerId: focused
          ? _HomeMapScreenState._emptyFeatureCollection
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

  /// Rebuilds the cluster/per-type marker feature lists from [_areaStops] using
  /// the current camera. Client-side screen-space grid clustering (the maplibre
  /// 0.3.x GeoJsonSource has no native clustering).
  void _rebuildMarkerFeatures() {
    final controller = _controller;
    final favoriteIds = _favoriteIds;
    final visibleStops = [
      for (final s in _areaStops)
        if (!favoriteIds.contains(s.stopId)) s,
    ];

    final clusters = <Feature<Point>>[];
    final bus = <Feature<Point>>[];
    final tram = <Feature<Point>>[];
    final trolley = <Feature<Point>>[];
    final mixed = <Feature<Point>>[];

    void addIndividual(Stop s) {
      final feature = Feature<Point>(
        geometry: Point(Geographic(lon: s.lon, lat: s.lat)),
        properties: {'stopId': s.stopId, 'name': s.name},
      );
      final type = stopMarkerType(s);
      if (type == null) {
        mixed.add(feature); // one unified marker for multi-type stops (D2)
        return;
      }
      switch (type) {
        case VehicleType.tram:
          tram.add(feature);
        case VehicleType.trolleybus:
          trolley.add(feature);
        case VehicleType.bus:
          bus.add(feature);
      }
    }

    final zoom = controller?.getCamera().zoom ?? 14;
    if (controller == null || zoom >= _individualZoom) {
      for (final s in visibleStops) {
        addIndividual(s);
      }
    } else {
      const cell = 66.0;
      final buckets = <String, List<Stop>>{};
      for (final s in visibleStops) {
        final off = controller.toScreenLocation(
          Geographic(lon: s.lon, lat: s.lat),
        );
        final key = '${(off.dx / cell).floor()}:${(off.dy / cell).floor()}';
        buckets.putIfAbsent(key, () => []).add(s);
      }
      for (final bucket in buckets.values) {
        if (bucket.length == 1) {
          addIndividual(bucket.first);
        } else {
          var lat = 0.0, lon = 0.0;
          for (final s in bucket) {
            lat += s.lat;
            lon += s.lon;
          }
          clusters.add(
            Feature<Point>(
              geometry: Point(
                Geographic(lon: lon / bucket.length, lat: lat / bucket.length),
              ),
              properties: {'cluster': true, 'point_count': bucket.length},
            ),
          );
        }
      }
    }

    _clusterPts = clusters;
    _busPts = bus;
    _tramPts = tram;
    _trolleyPts = trolley;
    _mixedPts = mixed;
    _pushStopSources();
  }

  Set<String> get _favoriteIds =>
      (ref.read(favoriteStopLocationsProvider).valueOrNull ?? const <Stop>[])
          .map((s) => s.stopId)
          .toSet();

  // ---- Live vehicles in the viewport ---------------------------------------

  /// Loads vehicles for the viewport. [force] bypasses the "viewport hasn't
  /// moved" guard — used by the periodic timer (to refresh positions in place)
  /// and the first load; camera-idle events pass it false so merely re-emitted
  /// idles don't hammer the source.
  Future<void> _loadVehiclesForVisibleArea({bool force = false}) async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final camera = controller.getCamera();
    if (_currentZoom != camera.zoom) {
      _setState(() => _currentZoom = camera.zoom);
    }
    // On-demand mode (vehicles_on_demand): no background "aquarium" — the map
    // fetches and renders no vehicles without a context. Markers come only from
    // a stop context (the arrivals listener) or an injected followed vehicle, so
    // the map fan-out load (× every open client × 30s) is dropped entirely here.
    if (_onDemand) return;
    // No zoom gate on fetching (F5): the request is always bounded to ≤1 km /
    // ≤12 stops (see _vehiclesMaxRadius and the backend fan-out cap) regardless
    // of zoom, so a zoomed-out view never fans the source out wider. Keeping it
    // live means the city overview still shows the (sparse) vehicles already
    // around the viewport as dots instead of a blank map; the marker layer
    // degrades pills → dots at low zoom on its own. When even the
    // bounded area is empty, a hint tells the user to zoom in (see _zoomHint).
    final center = ll.LatLng(camera.center.lat, camera.center.lon);
    final radius = _radiusForVisibleArea(
      camera,
    ).clamp(400.0, _vehiclesMaxRadius);
    if (!force && _lastVehiclesCenter != null) {
      final moved = _distance.as(
        ll.LengthUnit.Meter,
        _lastVehiclesCenter!,
        center,
      );
      if (moved < radius * 0.3)
        return; // viewport barely changed — skip refetch
    }
    final seq = ++_vehiclesRequestSeq;
    _lastVehiclesCenter = center;
    try {
      final fetched = await ref
          .read(vehiclesRepositoryProvider)
          .nearby(
            lat: center.latitude,
            lon: center.longitude,
            radiusMeters: radius,
          );
      // Re-check the flag AFTER the await: a fetch kicked off while off-demand
      // (e.g. in the window after a reload, before `/config` resolves the flag to
      // ON) must NOT populate the map once we're on-demand — otherwise the whole
      // aquarium (buses, trams, scheduled objects) leaks onto a context-less map.
      if (!keepAquariumResult(
        mounted: mounted,
        current: seq == _vehiclesRequestSeq,
        onDemand: _onDemand,
      )) {
        return;
      }
      // Placeholder rows (junk garage `P1..P999`, GPS pinned to a stop) aren't
      // tracked vehicles — they'd sit motionless on a stop, so keep them off the
      // map. The arrivals *list* on the stop screen still shows their line/ETA.
      // Scheduled objects are schedule-derived by design, so they bypass this
      // junk filter.
      final vehicles = fetched
          .where(
            (v) =>
                v.source == VehicleSource.scheduled ||
                areaVehicleHasLivePosition(v),
          )
          .toList();
      // Hybrid live+schedule: render whatever the backend sends, live and
      // schedule-predicted alike. (The backend de-dups a scheduled trip that has
      // a live vehicle; the client's key-prefixing keeps the two off the same
      // track.) Scheduled objects are present only where the map endpoint emits
      // them; elsewhere this is just the live set.
      final shown = vehicles;
      // Which shape to move each vehicle along: the *direction the vehicle is
      // actually going* (backend-resolved route_id) so it doesn't ride the
      // canonical direction's street ("through houses"). A null key (older
      // payload) just means no path → straight-line ease (safe).
      String? shapeKeyOf(AreaVehicle v) => v.routeId;
      // Make sure each visible route's geometry is (being) fetched so the
      // animator can move markers along the road, not through buildings (X5) —
      // and, in timed mode, project the plan onto it.
      _ensureShapesFor(
        [for (final v in shown) shapeKeyOf(v)].whereType<String>(),
        byRouteId: true,
      );
      _lastShownVehicles = shown;
      _vehAnimator.syncSamples(_buildVehicleSamples(shown), _vehAnim.value);
      // Drive the layer whenever a fix brings motion (foregrounded); otherwise
      // settle so a screen of stationary vehicles renders zero frames until the
      // next move. Always run the 30s ease controller here — NOT only when
      // timed is off: a vehicle whose route geometry/plan isn't available yet
      // (shape still loading, or no trajectory) falls back to the conservative
      // ease, and that ease needs the controller's t-ramp to move at all.
      // Without it such a fallback vehicle would sit pinned at its last fix and
      // jump on the next refetch. In timed mode the wall-clock ticker also runs
      // (it advances the timed players and repaints); the two coexist — the
      // ticker reads each track's live position, easing for fallback tracks,
      // wall-clock for timed ones.
      if (!_paused && _vehAnimator.hasPendingMotion) {
        _vehAnim.forward(from: 0);
        _startVehDriver();
      } else {
        _stopVehDriver();
        _vehAnim.value =
            1; // land straight on the latest fixes, no per-frame ease
      }
      // Always push the fresh set to the render path right away, so newly-entered
      // vehicles appear and departed ones drop this frame (not only on the next
      // ticker tick). The symbol source is write-driven — unlike the widget path
      // it doesn't self-heal on every rebuild — so the set membership must be
      // written on every sync.
      _paintVehicles();
      // Reflect the animator's set (which may still hold briefly-missing
      // vehicles during their grace period), not just this response (X6).
      _setState(() => _hasVehicles = _vehAnimator.tracks.isNotEmpty);
    } catch (_) {
      // Keep whatever is shown on a transient failure.
    }
  }

  /// Lazily fetches (once, cached) the route geometry for each given key so
  /// vehicles on it can be animated along the route. Keys are direction route_ids
  /// when [byRouteId] (fetched by route_id), else line numbers (fetched by
  /// number). A failed lookup caches null — the vehicle then falls back to a
  /// plain straight-line ease. Route_ids and line numbers don't collide, so the
  /// one cache safely holds both across a flag flip.
  void _ensureShapesFor(Iterable<String> keys, {required bool byRouteId}) {
    final repo = ref.read(linesRepositoryProvider);
    for (final key in keys.toSet()) {
      if (_shapeCache.containsKey(key) || _shapeFetching.contains(key)) {
        continue;
      }
      _shapeFetching.add(key);
      (byRouteId ? repo.getShapeByRouteId(key) : repo.getShapeByLineNumber(key))
          .then((shape) {
            final path = RoutePath.fromLatLon(shape.polyline);
            _shapeCache[key] = path;
            // The shape landed after the sync that needed it: re-apply the
            // current set so any timed track still on the plan-point chord
            // fallback upgrades to this road geometry now (~fetch latency)
            // instead of driving straight "through buildings" until the next
            // 30s poll. updatePlan re-anchors onto the new path without a jump.
            if (path != null && path.isUsable) _scheduleVehicleResync();
          })
          .catchError((_) {
            _shapeCache[key] = null;
          })
          .whenComplete(() => _shapeFetching.remove(key));
    }
  }

  /// Build the animator samples for a vehicle set from the current flags and the
  /// (possibly just-updated) shape cache. Self-contained so both the 30s poll
  /// and the shape-load re-sync produce identical samples.
  List<VehicleSample> _buildVehicleSamples(List<AreaVehicle> shown) {
    String? shapeKeyOf(AreaVehicle v) => v.routeId;
    return [
      for (final v in shown)
        VehicleSample(
          key: v.key,
          position: ll.LatLng(v.lat, v.lon),
          line: v.line,
          // The feed's authoritative per-line type (route_type), resolved
          // backend-side — same source the stop markers now use, so a line's
          // vehicles and its stops always agree.
          type: v.vehicleType,
          heading: v.heading,
          // Stitch to the direction-resolved shape when available (fixes
          // "through houses"); null key ⇒ no path ⇒ straight-line ease.
          path: shapeKeyOf(v) == null ? null : _shapeCache[shapeKeyOf(v)!],
          // Same resolved direction, so a marker-tap follow highlights the
          // correct-direction route + stops rather than the line default.
          directionRouteId: shapeKeyOf(v),
          // Hand the animator each vehicle's forward plan + as-of time so it
          // plays motion forward by time; a vehicle without a plan (null) just
          // eases conservatively to its latest fix.
          trajectory: v.trajectory,
          asOf: v.asOf,
          source: v.source,
        ),
    ];
  }

  /// Debounced re-sync after a route shape finishes loading (see
  /// [_ensureShapesFor]). Coalesces a burst of shape loads into one animator
  /// re-sync so a newly-fetched road geometry replaces the chord fallback
  /// promptly, without resetting the 30s ease ramp (that would nudge fallback
  /// tracks) — timed tracks upgrade their path in place via updatePlan.
  void _scheduleVehicleResync() {
    _shapeResyncTimer?.cancel();
    _shapeResyncTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _lastShownVehicles.isEmpty) return;
      _vehAnimator.syncSamples(
        _buildVehicleSamples(_lastShownVehicles),
        _vehAnim.value,
      );
      if (!_paused && _vehAnimator.hasPendingMotion) {
        _startVehDriver();
      }
      _paintVehicles();
    });
  }

  /// Highlight a line's route on this same map (hiding the rest) instead of
  /// pushing a separate screen — driven by a vehicle tap, a followed vehicle, or
  /// a favourite-line tap. Closing the focus panel restores normal browsing.
  ///
  /// The camera deliberately stays where the user left it (F2): highlighting a
  /// route must not yank the user out to a whole-route fitBounds. The camera is
  /// handled by the caller (follow mode / none), never here.
  ///
  /// [refreshVehicles] refetches the viewport vehicle set so the focused line's
  /// buses show at once; the §C path passes false so a just-injected followed
  /// marker can't be pruned by a fan-out that doesn't (yet) contain it.
  Future<void> _openVehicleLine(
    String line, {
    String? directionRouteId,
    bool scheduled = false,
    bool refreshVehicles = true,
  }) async {
    _clearSearch();
    try {
      // Highlight the SAME direction the marker travels. A bare line number
      // resolves to the line's default direction (dir 0) — the opposite
      // carriageway when the vehicle runs the other way — so the route line and
      // its stop pins landed on the wrong side. With the resolved direction
      // route_id we fetch that variant's shape + stops instead.
      final repo = ref.read(linesRepositoryProvider);
      final shape = directionRouteId != null
          ? await repo.getShapeByRouteId(directionRouteId)
          : await repo.getShapeByLineNumber(line);
      if (!mounted) return;
      // No usable geometry for this line (a suburban / non-GSP carrier like
      // "Ada 4" isn't in our GTFS — no shape, no stations, no direction). Follow
      // still works off raw GPS, but there's nothing to highlight or list, so
      // degrade honestly (owner R4 #2): no route line, no route ahead, an honest
      // label, and the marker driven by GPS instead of a phantom station plan
      // (which straight-lines between far-apart stations → "through the houses").
      if (shape.polyline.length < 2 && shape.stops.isEmpty) {
        _enterRawFollow();
        return;
      }
      _followNoRouteData = false;
      final routeStops = shape.stops
          .map(
            (s) => Stop(
              stopId: s.stopId,
              name: s.name,
              lat: s.lat,
              lon: s.lon,
              lines: [line],
            ),
          )
          .toList();
      // Cache the geometry so the focused line's vehicles ease along the road.
      if (shape.polyline.length >= 2) {
        _shapeCache[line] = RoutePath.fromLatLon(shape.polyline);
      }
      _setState(() {
        _focus = _LineFocus(
          line: line,
          type: shape.vehicleType,
          origin: shape.origin,
          destination: shape.destination,
          polyline: shape.polyline,
          stops: routeStops,
          scheduled: scheduled,
        );
      });
      _pushStopSources(); // hide the ambient stop layers behind the focused line
      _syncFocusLayers(); // draw the route + its stops UNDER the vehicle symbols
      // Refresh the vehicle set so the focused line's buses show right away.
      if (refreshVehicles) _loadVehiclesForVisibleArea(force: true);
    } catch (_) {
      // A failed shape lookup means we have no geometry for this line either —
      // same honest raw-GPS degradation as an empty shape (owner R4 #2).
      _enterRawFollow();
    }
  }

  /// The followed line has no route geometry in our GTFS (owner R4 #2): drive the
  /// marker off raw GPS (drop the station plan that would straight-line it
  /// through the houses), draw no route line, and let the vehicle view show an
  /// honest "route unavailable" note in place of the stop list.
  void _enterRawFollow() {
    if (!mounted) return;
    _setState(() {
      _followNoRouteData = true;
      _focus = null; // no route/stops to draw
    });
    _syncFocusLayers(); // remove any stale focus layers
    final key = _selectedVehicleKey;
    if (key != null) {
      // Re-drive this marker by GPS alone: clear its timed plan so it eases to
      // its live fix instead of playing a plan over roads we don't have.
      _vehAnimator.dropTimed(key);
      _paintVehicles();
    }
  }

  // ---- Follow mode ----------------------------------------------------------

  /// Build one animator sample from an arrival's own data. The [shapeKey] is the
  /// direction route_id whose geometry the marker moves along; [asOf] anchors the
  /// timed-trajectory plan (the arrivals board's `updated_at`).
  VehicleSample _sampleFromArrival(
    Arrival a,
    String shapeKey, {
    DateTime? asOf,
  }) {
    return VehicleSample(
      key: VehicleTrackAnimator.keyFor(a),
      position: ll.LatLng(a.gps!.lat, a.gps!.lon),
      line: a.line,
      type: a.vehicleType,
      heading: a.heading,
      path: _shapeCache[shapeKey],
      trajectory: a.trajectory,
      asOf: asOf,
      // [shapeKey] IS the resolved direction route_id the marker moves along, so
      // a follow highlights the route + stops for that same direction.
      directionRouteId: shapeKey,
      source: a.scheduled ? VehicleSource.scheduled : VehicleSource.live,
    );
  }

  /// Run a programmatic camera move bracketed so its resulting move-start event
  /// (fired synchronously on web) is recognised as ours, not a user gesture.
  void _selfMove(void Function() move) {
    _selfCameraMove = true;
    try {
      move();
    } finally {
      _selfCameraMove = false;
    }
  }
}
