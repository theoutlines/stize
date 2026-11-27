part of '../home_map_screen.dart';

// Live vehicles in the viewport: fetch, shapes per line, samples for the
// animator, resync timer, and opening a vehicle's line (follow entry).

extension _MapVehicles on _HomeMapScreenState {
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
    // bounded area is empty, a hint tells the user to zoom in (see MapZoomHint).
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
      _shapes.lastShown = shown;
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
  /// number). A line with no shape caches null (raw GPS, owner R4 #2); a failed
  /// lookup is retried after [_shapeRetryAfter]. Route_ids and line numbers don't
  /// collide, so the one cache safely holds both.
  void _ensureShapesFor(Iterable<String> keys, {required bool byRouteId}) {
    final repo = ref.read(linesRepositoryProvider);
    final now = DateTime.now();
    for (final key in keys.toSet()) {
      if (_shapes.byLine.containsKey(key) || _shapes.fetching.contains(key)) {
        continue;
      }
      final failed = _shapes.failedAt[key];
      if (failed != null &&
          now.difference(failed) < _HomeMapScreenState._shapeRetryAfter) {
        continue;
      }
      _shapes.fetching.add(key);
      (byRouteId ? repo.getShapeByRouteId(key) : repo.getShapeByLineNumber(key))
          .then((shape) {
            final path = RoutePath.fromLatLon(shape.polyline);
            _shapes.byLine[key] = path;
            _shapes.failedAt.remove(key);
            if (path == null || !path.isUsable || !mounted) return;
            // The shape landed after the sample that needed it: put every
            // vehicle of this direction on the road now, whichever feed drew it
            // (the viewport set, a stop's board, a followed vehicle), instead of
            // leaving it at its raw fix until the next 30s poll.
            if (byRouteId &&
                _vehAnimator.adoptPath(key, path, _vehAnim.value)) {
              if (!_paused && _vehAnimator.hasPendingMotion) {
                _startVehDriver();
              }
              _paintVehicles();
            }
            _scheduleVehicleResync();
          })
          .catchError((_) {
            _shapes.failedAt[key] = DateTime.now();
          })
          .whenComplete(() => _shapes.fetching.remove(key));
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
          // "through houses"); without it the marker holds its raw GPS fix.
          path: shapeKeyOf(v) == null ? null : _shapes.byLine[shapeKeyOf(v)!],
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
  /// re-sync so a newly-fetched road geometry replaces the raw-fix fallback
  /// promptly, without resetting the 30s ease ramp (that would nudge fallback
  /// tracks) — timed tracks upgrade their path in place via updatePlan.
  void _scheduleVehicleResync() {
    _shapes.resyncTimer?.cancel();
    _shapes.resyncTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _shapes.lastShown.isEmpty) return;
      _vehAnimator.syncSamples(
        _buildVehicleSamples(_shapes.lastShown),
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
      _follow.noRouteData = false;
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
        _shapes.byLine[line] = RoutePath.fromLatLon(shape.polyline);
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
      _follow.noRouteData = true;
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
}
