part of '../home_map_screen.dart';

extension _MapContext on _HomeMapScreenState {
  // ---- On-demand stop context (state B) ------------------------------------

  /// Enter (or re-enter) stop context: the tapped stop's live arrivals become
  /// the only vehicle markers, fed from the same arrivals provider the sheet
  /// watches (shared fetch, no second fan-out). No-op unless the flag is on.
  ///
  /// The host — not the sheet — owns keeping this fresh: [_refreshTick] re-fetches
  /// this stop every 30s while the context is alive (crucially, also during a
  /// follow after the sheet has closed, so nothing freezes). Because our
  /// subscription pins the provider alive, a re-open would otherwise show a stale
  /// board ("Updated 2 min ago"), so we invalidate on entry to pull a fresh one
  /// (SWR: instant cached value, immediate revalidate).
  void _enterStopContext(String stopId) {
    if (!_onDemand) return;
    if (_stopContextId != stopId || _stopArrivalsSub == null) {
      _stopArrivalsSub?.close();
      _stopContextId = stopId;
      _stopArrivalsSub = ref.listenManual<AsyncValue<ArrivalsBoard>>(
        arrivalsProvider(stopId),
        (_, next) {
          final board = next.valueOrNull;
          if (board != null) _applyStopContextMarkers(board);
        },
      );
    }
    _returnToStopId = null;
    // Apply whatever is already in hand for an instant paint, then force a fresh
    // fetch so neither the markers nor the sheet show a stale board on open.
    final current = _stopArrivalsSub!.read().valueOrNull;
    if (current != null) _applyStopContextMarkers(current);
    ref.invalidate(arrivalsProvider(stopId));
  }

  /// Replace the vehicle set with this stop's live-position arrivals (schedule
  /// rows and P1..P999 placeholders have no real fix and stay list-only). Same
  /// animator/driver path as the background feed, so motion/timed-trajectory and
  /// spiderfy behave identically.
  void _applyStopContextMarkers(ArrivalsBoard board) {
    if (!_onDemand || _stopContextId != board.stopId) return;
    final samples = <VehicleSample>[];
    final shapeKeys = <String>[];
    for (final a in board.arrivals) {
      if (!arrivalHasLivePosition(a)) continue;
      final dirId = a.directionRouteId ?? a.routeId;
      shapeKeys.add(dirId);
      samples.add(_sampleFromArrival(a, dirId, asOf: board.updatedAt));
    }
    _ensureShapesFor(shapeKeys, byRouteId: true);
    _vehAnimator.syncSamples(samples, _vehAnim.value);
    // A no-route follow re-adds the followed vehicle's board plan on every
    // refresh; keep it in raw-GPS mode so it doesn't resume driving "through the
    // houses" over a route we can't render (owner R4 #2).
    if (_follow.noRouteData && _selectedVehicleKey != null) {
      _vehAnimator.dropTimed(_selectedVehicleKey!);
    }
    // Diagnostics (staging overlay): board freshness + how many of this stop's
    // rows carried a timing plan, so a "frozen markers" report can be read off
    // the screen without a console (debugPrint is stripped in release web).
    _diag.ctxBoardAgeSec = DateTime.now()
        .toUtc()
        .difference(board.updatedAt.toUtc())
        .inSeconds;
    _diag.boardAgePolls.add(_diag.ctxBoardAgeSec!);
    if (_diag.boardAgePolls.length > 12) _diag.boardAgePolls.removeAt(0);
    _diag.ctxLive = samples.length;
    _diag.ctxWithTraj = samples.where((s) => s.trajectory != null).length;
    // Keep the driver alive for the whole poll interval whenever this context has
    // live timed markers — the timed players are advanced by wall-clock each
    // frame, and `hasForwardMotion` can momentarily read false as a fix converges
    // (especially near the 45s staleness gate). Parking the ticker on that flicker
    // is exactly what froze the markers mid-interval. Running the ease controller
    // holds `isAnimating` true across the interval so the ticker keeps advancing
    // them; a genuinely stale/stationary marker just repaints in place. (A context
    // is a handful of vehicles the user is watching, so this doesn't touch the
    // whole-city "idle = 0 frames" thermal budget.)
    final hasLiveTimed = _diag.ctxWithTraj > 0;
    if (!_paused && (hasLiveTimed || _vehAnimator.hasPendingMotion)) {
      _vehAnim.forward(from: 0);
      _startVehDriver();
    } else {
      _stopVehDriver();
      _vehAnim.value = 1;
    }
    _paintVehicles();
    _setState(() => _hasVehicles = _vehAnimator.tracks.isNotEmpty);
  }

  /// Leave stop context. Drops the subscription; clears the markers only when no
  /// vehicle is being followed (a followed vehicle keeps its injected marker).
  void _exitStopContext() {
    _stopArrivalsSub?.close();
    _stopArrivalsSub = null;
    _stopContextId = null;
    if (_selectedVehicleKey == null) {
      _vehAnimator.clear();
      _paintVehicles();
      _setState(() => _hasVehicles = false);
    }
  }

  /// React to the mode changing — the flag resolving at startup, or the user
  /// flipping the Settings choice. Applies on the fly, no restart.
  void _onOnDemandChanged() {
    if (!mounted) return;
    if (_onDemand) {
      // Entering on-demand: the background aquarium goes at once (and the 30s
      // tick stops fetching it — see mapRefreshAction). The contexts survive:
      // a followed vehicle keeps its own marker (§C, works in both modes)…
      final followed = _selectedVehicleKey;
      _vehAnimator.retainOnly({if (followed != null) followed});
      // …and a stop context repaints from the board already in hand instead of
      // waiting out the next 30s tick.
      final board = _stopContextId == null
          ? null
          : _stopArrivalsSub?.read().valueOrNull;
      if (board != null) {
        _applyStopContextMarkers(board);
      } else {
        _paintVehicles();
        _setState(() => _hasVehicles = _vehAnimator.tracks.isNotEmpty);
      }
    } else {
      // Left on-demand → repopulate the background set for the viewport.
      _loadVehiclesForVisibleArea(force: true);
    }
  }

  /// Close the vehicle context (line panel / back). Stops following, clears the
  /// route highlight, and — when on-demand — returns to the stop context it was
  /// opened from (state B) or to the empty map (state A).
  void _closeVehicleContext() {
    _stopFollow();
    _clearFocus();
    // The anchors belong to the follow that just ended: a later marker-tap
    // follow must not inherit them.
    _follow.stopsRemaining = null;
    _follow.etaMinutes = null;
    _follow.boardStop = null;
    _follow.boardStopId = null;
    final returnStop = _onDemand ? _returnToStopId : null;
    _returnToStopId = null;
    if (returnStop != null) {
      // Returning to the stop: reopening it re-pans the camera so the stop sits
      // above the sheet — don't also restore the pre-follow centre (it would
      // fight that), just reopen.
      _follow.preCenter = null;
      _follow.preZoom = null;
      _openStopById(returnStop);
      return;
    }
    // No stop to reopen: ease back to where the user came from. Prefer the
    // pre-stop viewport when the follow was spawned from a stop sheet we're not
    // reopening (so we land back at the original browse position, not the panned
    // stop), else the pre-follow viewport (a follow straight from Nearby).
    final center = _preStopCameraCenter ?? _follow.preCenter;
    final zoom = _preStopCameraCenter != null
        ? _preStopCameraZoom
        : _follow.preZoom;
    if (center != null) {
      _camEase(center, zoom: zoom);
    }
    _follow.preCenter = null;
    _follow.preZoom = null;
    _preStopCameraCenter = null;
    _preStopCameraZoom = null;
    if (_onDemand) _exitStopContext();
  }

  // ---- Adaptive context slot ------------------------------------------------

  /// The active panel view, derived from the SAME state the legacy flow uses:
  /// a tapped Fleet model (leaf) → model; a followed vehicle → vehicle; a slot
  /// stop → stop; else nearby. Desktop-only (the panel).
  ContextView get _activeView {
    if (_selectedVehicleKey != null || _focus != null)
      return ContextView.vehicle;
    if (_levels.isEmpty) return ContextView.nearby;
    return switch (_levels.last) {
      _MyStopsLevel() => ContextView.myStops,
      _GuideLevel() => ContextView.guide,
      _SettingsLevel() => ContextView.settings,
      _FeedbackLevel() => ContextView.feedback,
      _StopLevel() => ContextView.stop,
    };
  }

  /// Follow is interrupted: a vehicle context is up but we're not tracking (the
  /// user panned it away, or the vehicle left the viewport). Drives the
  /// conditional "Back to vehicle" pill (decision #8). Desktop-panel only.
  bool get _followLost =>
      _panelActive && _selectedVehicleKey != null && !_follow.active;

  /// The insets of the map NOT covered by the panel — the region a followed
  /// target must stay CENTRED inside (decision #3). Desktop-panel only.
  ///
  /// Analytic (no reliance on maplibre `padding`, whose web behaviour is
  /// inconsistent and drifts a delta-panned follow): the map centre is shifted
  /// WEST by half the panel width, so [target] lands in the middle of the
  /// unobscured strip to the right of the panel. On mobile / flag-OFF the panel
  /// is inactive → returns [target] unchanged (prod camera behaviour untouched).
  ///
  /// Back one step up the chain (model → vehicle → stop → nearby). The panel's
  /// single nav-row back arrow and Android back both route here; there is NO
  /// separate × — back IS the exit (owner R1 #4).
  void _slotBack() {
    if (_slotModel != null) {
      _setState(() => _slotModel = null);
      return;
    }
    switch (_activeView) {
      case ContextView.vehicle:
        _closeVehicleContext();
      case ContextView.stop:
      case ContextView.myStops:
      case ContextView.guide:
      case ContextView.settings:
      case ContextView.feedback:
        _popLevel();
      case ContextView.nearby:
        break;
    }
  }

  /// Open the Fleet model as a leaf sub-view INSIDE the panel (desktop) — never
  /// a second surface over it (owner R1 #3). On mobile this isn't used (the
  /// legacy modal card runs instead).
  void _openSlotModel(
    FleetVehicle fleet, {
    String? garageNo,
    required VehicleType type,
  }) {
    _setState(
      () => _slotModel = (fleet: fleet, garageNo: garageNo, type: type),
    );
  }

  /// The "Back to vehicle" pill: recenter on the vehicle (in the visible strip)
  /// and resume follow (decision #8).
  void _resumeFollowFromPill() {
    final key = _selectedVehicleKey;
    if (key == null || _vehAnimator.trackFor(key) == null) return;
    final pos = _vehAnimator.positionOf(key, _vehAnim.value);
    _startFollow(key, target: pos, flyTo: true);
    if (mounted) _setState(() {});
  }

  /// Enter vehicle context from a tapped arrival row (§C). Builds a guaranteed
  /// marker from the arrival's own data (gps + trajectory + direction) so the
  /// vehicle appears immediately — never waiting on a viewport fan-out, which was
  /// the root of the old bug — highlights its direction's route, flies to it and
  /// follows. Works at both flag values.
  void _focusVehicleFromArrival(
    Arrival a,
    DateTime asOf, {
    required String source,
  }) {
    final gps = a.gps;
    // No live fix → no marker → don't enter follow (it would be a follow over an
    // empty map). Surface "vehicle lost" instead.
    if (gps == null || !arrivalHasLivePosition(a)) {
      _showVehicleLost();
      return;
    }
    _clearSearch();
    // Slot ON: return up the chain to the slot's stop view (works in aquarium
    // mode too, where there's no on-demand `_stopContextId`). Legacy: only the
    // on-demand stop context.
    _returnToStopId = _slotStopId ?? (_onDemand ? _stopContextId : null);
    final key = VehicleTrackAnimator.keyFor(a);
    final pos = ll.LatLng(gps.lat, gps.lon);
    final dirId = a.directionRouteId ?? a.routeId;
    _ensureShapesFor([dirId], byRouteId: true);
    // Guaranteed marker: upsert this one vehicle without disturbing others.
    _vehAnimator.syncSamples(
      [_sampleFromArrival(a, dirId, asOf: asOf)],
      _vehAnim.value,
      prune: false,
    );
    // The marker must actually exist before we commit to follow.
    if (_vehAnimator.trackFor(key) == null) {
      _showVehicleLost();
      return;
    }
    // Anchor the worded-route ETAs (R1 #5) to this arrival's own numbers.
    _follow.stopsRemaining = a.stopsRemaining;
    _follow.etaMinutes = a.etaMinutes;
    final ctxStop = _slotStopId ?? _stopContextId;
    _follow.boardStop = ctxStop == null
        ? null
        : _resolveStopLatLngSync(ctxStop);
    _follow.boardStopId = ctxStop;
    // Single follow entry (fly the camera in from a list row). refreshVehicles
    // false so a fan-out can't prune the marker we just injected.
    _enterFollow(
      key: key,
      target: pos,
      flyTo: true,
      line: a.line,
      source: source,
      scheduled: a.scheduled,
    );
    // Sitting on a vehicle = get its FRESHEST state now, don't wait out the ~30s
    // poll (owner R3 #2). If the board this row came from was stale (a HOLD fix),
    // forcing an immediate refetch collapses the desync window from ~30s to a
    // fraction of a second: a fresh board re-anchors the marker (an honest
    // catch-up jerk to the real spot), and the route ahead stops being fresher
    // than the marker. Until it lands, the stale-board gate keeps the marker on
    // an honest HOLD rather than animating a stale plan.
    if (ctxStop != null) ref.invalidate(arrivalsProvider(ctxStop));
  }

  void _clearFocus() {
    if (_focus == null && _selectedVehicleKey == null) return;
    _setState(() {
      _focus = null;
      _selectedVehicleKey = null;
      _slotModel = null; // the model leaf belongs to the vehicle view
      _follow.noRouteData = false;
    });
    _pushStopSources(); // restore the ambient stop layers
    _syncFocusLayers(); // remove the focus route/stops layers
    // Drop the tap highlight on the symbol layer.
    _writeVehiclesToSource();
  }

  // ---- Taps -----------------------------------------------------------------

  void _handleTap(Geographic point) {
    final controller = _controller;
    if (controller == null) return;
    final screen = controller.toScreenLocation(point);
    final rect = Rect.fromCircle(center: screen, radius: 22);
    // Symbol-layer vehicles: hit-test the badge layer and open the tapped line
    // (a bottom sheet). Highlight the selected vehicle via its feature
    // `selected` flag.
    if (_vehLayerAdded) {
      final vehicleFeatures = controller.featuresInRect(
        rect,
        layerIds: movingObjectsTapLayerIds,
      );
      for (final f in vehicleFeatures) {
        final line = f.properties['label'];
        if (line is String && line.isNotEmpty) {
          final key = f.properties['key'];
          final keyStr = key is String ? key : null;
          // Honestly mark a schedule-predicted object when its line opens.
          final scheduled =
              keyStr != null &&
              _vehAnimator.trackFor(keyStr)?.source == VehicleSource.scheduled;
          // §C.2: highlight the route + line panel and start following — but the
          // camera does NOT jump or zoom (don't regress F2). Same single entry
          // as the list-row paths, so all three end in identical state.
          // Slot ON: return up the chain to the slot's stop view (works in aquarium
          // mode too, where there's no on-demand `_stopContextId`). Legacy: only the
          // on-demand stop context.
          _returnToStopId = _slotStopId ?? (_onDemand ? _stopContextId : null);
          if (keyStr != null) {
            _enterFollow(
              key: keyStr,
              target: ll.LatLng(point.lat, point.lon),
              flyTo: false,
              line: line,
              source: Ev.srcMarker,
              scheduled: scheduled,
              refreshVehicles: true,
            );
          } else {
            _openVehicleLine(line, scheduled: scheduled);
          }
          return;
        }
      }
    }
    final features = controller.featuresInRect(rect);
    // Stops: the fat tap rect can cover several pins in a dense cluster, and
    // featuresInRect returns them in query/z order — the FIRST isn't necessarily
    // the one under the finger. Collect every candidate stop, project it to the
    // screen, and open the one NEAREST the tap point (#2, "tap opens a neighbour").
    final stopCandidates = <(Stop, Offset)>[];
    for (final f in features) {
      final stopId = f.properties['stopId'];
      if (stopId is String) {
        final stop = _stopById(stopId);
        if (stop != null) {
          try {
            final at = controller.toScreenLocation(
              Geographic(lon: stop.lon, lat: stop.lat),
            );
            stopCandidates.add((stop, at));
          } catch (_) {
            stopCandidates.add((
              stop,
              screen,
            )); // projection failed — treat as at the tap
          }
        }
      }
    }
    final nearestStop = pickNearest(screen, stopCandidates);
    if (nearestStop != null) {
      _openStop(nearestStop, source: Ev.srcPin);
      return;
    }
    for (final f in features) {
      final props = f.properties;
      if (props['cluster'] == true) {
        final camera = controller.getCamera();
        _camEase(point, zoom: (camera.zoom + 2).clamp(12, 18));
        return;
      }
    }
  }

  Stop? _stopById(String id) {
    for (final s in _stops.area) {
      if (s.stopId == id) return s;
    }
    // While a line is focused, its own stops are the ones on screen.
    for (final s in _focus?.stops ?? const <Stop>[]) {
      if (s.stopId == id) return s;
    }
    final favs =
        ref.read(favoriteStopLocationsProvider).valueOrNull ?? const <Stop>[];
    for (final s in favs) {
      if (s.stopId == id) return s;
    }
    return null;
  }
}
