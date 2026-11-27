part of '../home_map_screen.dart';

extension _MapGeometry on _HomeMapScreenState {
  // ---- Map geometry owner (single source of truth) --------------------------

  /// The mobile bottom sheet reported a new height. Feeds the geometry owner so
  /// a followed vehicle is kept above the sheet (the follow tick re-centres from
  /// [_mapInsets] each step). Thresholded to avoid a rebuild on every sub-pixel.
  void _setMobileSheetPx(double px) {
    if ((px - _mobileSheetPx).abs() < 4) return;
    _setState(() => _mobileSheetPx = px);
  }

  EdgeInsets get _mapInsets => mapInsetsFor(
    panelActive: _panelActive,
    panelWidth: panelWidthFor(MediaQuery.sizeOf(context).width),
    mobileSheetPx: _mobileSheetPx,
    panelCollapsed: _panelCollapsed,
  );

  /// Entering a context (stop / vehicle) while the panel is collapsed re-expands
  /// it so the new view is visible (owner A#4). The collapse is a view-only hide;
  /// the state machine already advanced, so this only flips the visibility flag.
  void _expandPanelIfCollapsed() {
    if (_panelActive && _panelCollapsed) {
      _setState(() => _panelCollapsed = false);
    }
  }

  /// Instant camera move (jumpTo) carrying the current geometry padding.
  void _camMove({Geographic? center, double? zoom}) {
    final c = _controller;
    if (c == null) return;
    _selfMove(
      () => c.moveCamera(center: center, zoom: zoom, padding: _mapInsets),
    );
  }

  /// Eased camera move (flyTo) carrying the current geometry padding. Returns the
  /// flight future so callers can act once it settles.
  Future<void>? _camEase(
    Geographic center, {
    double? zoom,
    Duration duration = _HomeMapScreenState._cameraEaseDuration,
    double webSpeed = _HomeMapScreenState._cameraEaseSpeed,
  }) {
    final c = _controller;
    if (c == null) return null;
    Future<void>? flight;
    _selfMove(() {
      flight = c.animateCamera(
        center: center,
        zoom: zoom,
        padding: _mapInsets,
        nativeDuration: duration,
        webSpeed: webSpeed,
        webMaxDuration: StizeMotion.cameraMax,
      );
    });
    return flight;
  }

  void _onMapGeometryChanged() {
    final c = _controller;
    if (c == null || !mounted) return;
    final focus = _cameraFocus();
    if (focus != null) {
      // A focus re-centres on itself in the new visible area — screen-math, so
      // both axes land correctly (same helper the follow tick uses).
      _centreOnVisibleArea(c, focus, animated: true);
    } else {
      // Free browse: re-easing to the CURRENT centre with the new padding shifts
      // the scene by the geometry delta (maplibre places the centre at the
      // padded centre) — the city slides by the delta, it isn't covered.
      _camEase(
        c.getCamera().center,
        duration: _HomeMapScreenState._geometryEaseDuration,
        webSpeed: 1.4,
      );
    }
  }

  /// The geographic point the camera should keep centred, if any: the followed
  /// vehicle, else the active stop context. Null = free browse.
  Geographic? _cameraFocus() {
    final key = _selectedVehicleKey;
    if (_follow.active && key != null && _vehAnimator.trackFor(key) != null) {
      final p = _vehAnimator.positionOf(key, _vehAnim.value);
      return Geographic(lon: p.longitude, lat: p.latitude);
    }
    final stopId = _slotStopId ?? _stopContextId;
    if (stopId != null) {
      final pos = _resolveStopLatLngSync(stopId);
      if (pos != null) return Geographic(lon: pos.longitude, lat: pos.latitude);
    }
    return null;
  }

  /// The single entry into follow mode. Every source — a stop-sheet row, a
  /// Nearby row, a marker tap — funnels through here so they establish an
  /// identical state set: select the vehicle, guarantee the follow bar (via the
  /// `_selectedVehicleKey`-gated bottom UI, which replaces whatever context sheet
  /// was open and offers the × exit), load its route, and start the camera
  /// follow. The caller has already ensured the marker exists.
  ///
  /// The Nearby path used to skip this contract — it nudged only camera+selection
  /// while its (persistent, non-modal) sheet stayed open and the follow bar,
  /// gated on the async route load, never appeared — so there was no way out.
  void _enterFollow({
    required String key,
    required ll.LatLng target,
    required bool flyTo,
    required String line,
    required String source,
    bool scheduled = false,
    bool refreshVehicles = false,
  }) {
    // Entering a vehicle context while collapsed re-expands the panel (A#4).
    _expandPanelIfCollapsed();
    // Single funnel for all three follow entries (marker / sheet / nearby), so
    // this one log point captures every "follow started" with its source.
    ref
        .read(eventLoggerProvider)
        .log(Ev.vehicleFollow, props: {'source': source});
    _setState(() => _selectedVehicleKey = key);
    // Mobile: the follow opens in the sheet at its low detent, the map on top.
    if (!_panelActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_sheetCtl.isAttached) return;
        if ((_sheetCtl.size - kSheetPeek).abs() < 0.01) return;
        _sheetCtl.animateTo(
          kSheetPeek,
          duration: StizeMotion.slow,
          curve: StizeMotion.smoothOut,
        );
      });
    }
    _writeVehiclesToSource(); // tap highlight on the symbol layer
    if (!_paused && _vehAnimator.hasPendingMotion) _startVehDriver();
    _paintVehicles();
    // Route highlight (sets `_focus` async). The follow bar no longer waits on
    // it — it shows the instant `_selectedVehicleKey` is set. Draw the highlight
    // for the vehicle's OWN resolved direction (from its track), not the line's
    // default — otherwise the route and its pins sit on the opposite carriageway.
    _openVehicleLine(
      line,
      directionRouteId: _vehAnimator.trackFor(key)?.directionRouteId,
      scheduled: scheduled,
      refreshVehicles: refreshVehicles,
    );
    _startFollow(key, target: target, flyTo: flyTo);
  }

  /// Start following [key]. [flyTo] true (entry from a list row) flies the camera
  /// to the vehicle and zooms to a readable pill first, then — once the fly-to
  /// settles — hands over to the continuous per-frame pan; false (a marker tap)
  /// starts tracking from where the camera already is, no jump, no zoom change
  /// (§C.2, don't regress F2).
  void _startFollow(
    String key, {
    required ll.LatLng target,
    required bool flyTo,
  }) {
    final controller = _controller;
    // Snapshot where the user is before we fly off, so closing the context can
    // bring them back here (the stop, or the pre-focus viewport). Only on a fresh
    // entry — a re-seed mid-follow must not overwrite the origin.
    if (!_follow.active && controller != null) {
      final cam = controller.getCamera();
      _follow.preCenter = cam.center;
      _follow.preZoom = cam.zoom;
    }
    _follow.active = true;
    _selectedVehicleKey = key; // (re)seed on the first follow tick
    final afterFlight = flyTo && controller != null;
    _follow.pacer.start(DateTime.now(), afterFlight: afterFlight);
    if (afterFlight) {
      final zoom = math.max(
        controller.getCamera().zoom,
        kMovingObjectDetailZoom,
      );
      // Fly the vehicle to the centre of the VISIBLE area — the geometry padding
      // (owned by [_mapInsets]) does the centring, on this and every later tick.
      final flight = _camEase(
        Geographic(lon: target.longitude, lat: target.latitude),
        zoom: zoom,
      );
      // Engage the continuous follow only once the fly-to has actually settled,
      // so the two never fight.
      flight?.whenComplete(() {
        if (mounted && _follow.active && _selectedVehicleKey == key) {
          _follow.pacer.engage();
        }
      });
    }
    // Ensure the layer paints (and the follow tick fires) even if the vehicle is
    // momentarily still; a moving vehicle keeps the driver alive on its own.
    _startVehDriver();
    _paintVehicles();
  }

  void _stopFollow() {
    if (!_follow.active) return;
    _follow.active = false;
    _follow.pacer.stop();
  }

  /// A brief "vehicle no longer tracked" notice — shown when we can't build a
  /// followed marker, or the followed vehicle drops out of the feed.
  void _showVehicleLost() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).vehicleLost)),
    );
  }

  /// The followed vehicle vanished mid-follow: notify and leave the vehicle
  /// context (back to the stop it came from, or the map), so follow never
  /// continues over an empty map.
  void _onFollowedVehicleLost() {
    if (!_follow.active) return;
    _showVehicleLost();
    _closeVehicleContext();
  }

  /// One follow step: place the marker at the centre of the VISIBLE area in
  /// BOTH axes. Uses screen-math (measure the marker's pixel, pan so it lands on
  /// the visible-area-centre pixel) rather than `moveCamera(center, padding)` —
  /// `jumpTo`'s padding shifted only the horizontal, which dropped vertical
  /// tracking (owner R3 #1). Screen-math moves x AND y explicitly, so the
  /// vehicle can't drift off vertically. Paced by [FollowPacer].
  void _followTick() {
    if (!_follow.active) return;
    // The fly-to normally engages follow when it settles; if its future was
    // dropped (an interrupted web flight never resolves), engage on time.
    if (!_follow.pacer.readyAt(DateTime.now())) return;
    final key = _selectedVehicleKey;
    final controller = _controller;
    if (key == null || controller == null) return;
    if (_vehAnimator.trackFor(key) == null) {
      // The vehicle dropped out of the feed for good (past the grace period).
      // Surface "vehicle lost" and leave follow rather than chase an empty map.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _onFollowedVehicleLost(),
      );
      return;
    }
    if (!_follow.pacer.moveDueAt(DateTime.now())) return;
    final pos = _vehAnimator.positionOf(key, _vehAnim.value);
    _centreOnVisibleArea(
      controller,
      Geographic(lon: pos.longitude, lat: pos.latitude),
      animated: false,
    );
  }

  /// Place [geo] at the centre of the VISIBLE area (the strip not covered by the
  /// panel / sheet) in BOTH axes, via screen-math. Independent of maplibre's
  /// padding (which this move sets to zero) — the target PIXEL already accounts
  /// for the overlap geometry, so x and y are both handled explicitly.
  void _centreOnVisibleArea(
    MapController c,
    Geographic geo, {
    required bool animated,
  }) {
    final size = MediaQuery.sizeOf(context);
    final insets = _mapInsets;
    final markerScreen = c.toScreenLocation(geo);
    // Centre of the visible (unobscured) area, in screen pixels — both axes.
    final target = Offset(
      insets.left + (size.width - insets.left - insets.right) / 2,
      insets.top + (size.height - insets.top - insets.bottom) / 2,
    );
    final windowCentre = Offset(size.width / 2, size.height / 2);
    // The new camera centre is the geo currently under this screen point; after
    // the move the marker sits exactly on [target].
    final newCentre = c.toLngLat(markerScreen + windowCentre - target);
    _diag.followCam =
        'FOLLOW mk(${markerScreen.dx.toStringAsFixed(0)},'
        '${markerScreen.dy.toStringAsFixed(0)}) '
        'tgt(${target.dx.toStringAsFixed(0)},${target.dy.toStringAsFixed(0)}) '
        'padL${insets.left.toStringAsFixed(0)}B${insets.bottom.toStringAsFixed(0)} '
        'cam(${newCentre.lat.toStringAsFixed(5)},${newCentre.lon.toStringAsFixed(5)})';
    final zoom = c.getCamera().zoom;
    _selfMove(() {
      if (animated) {
        c.animateCamera(
          center: newCentre,
          zoom: zoom,
          nativeDuration: _HomeMapScreenState._geometryEaseDuration,
          webSpeed: 1.4,
          webMaxDuration: StizeMotion.slow,
        );
      } else {
        // padding stays zero — the target pixel already encodes the geometry.
        c.moveCamera(center: newCentre, zoom: zoom);
      }
    });
  }
}
