part of '../home_map_screen.dart';

extension _MapSearch on _HomeMapScreenState {
  // ---- Search ---------------------------------------------------------------

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      _searchLogged = false; // a new non-empty query starts a fresh session
      _setState(() {
        _searching = false;
        _resultStops = [];
        _resultLines = [];
        _resultPlaces = [];
      });
      return;
    }
    // The results render in the panel body, which is hidden while collapsed —
    // so starting a search re-expands the panel (a search is a context entry,
    // owner A#4) to give the results (and the row you'll tap) somewhere to show.
    _expandPanelIfCollapsed();
    _setState(() => _searching = true);
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _runSearch(query),
    );
  }

  Future<void> _runSearch(String query) async {
    if (!_searchLogged) {
      _searchLogged = true;
      ref.read(eventLoggerProvider).log(Ev.searchUsed);
    }
    // Shared stop+line fan-out (one fork for both breakpoints — C#4).
    final results = await ref.read(globalSearchProvider).run(query);
    List<GeocodeResult> places = [];
    try {
      places = await ref.read(geocodeRepositoryProvider).search(query);
    } catch (_) {
      // Geocoding is best-effort, and desktop-only in the search scope.
    }
    if (!mounted) return;
    _setState(() {
      _resultStops = results.stops;
      _resultLines = results.lines;
      _resultPlaces = places;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _focusNode.unfocus();
    _searchLogged = false;
    _setState(() {
      _searching = false;
      _resultStops = [];
      _resultLines = [];
      _resultPlaces = [];
    });
  }

  void _openStop(Stop stop, {String? source}) => _openStopById(
        stop.stopId,
        stopName: stop.name,
        at: ll.LatLng(stop.lat, stop.lon),
        source: source,
      );

  /// Tap a "Nearby" row → follow that line+direction's soonest **live** vehicle
  /// (#5, owner variant 3). A NearbyGroup carries no gps/trajectory, so we resolve
  /// the vehicle from the same `/arrivals` the sheet uses (SWR-cached): the
  /// nearest live board of this line × direction. If the group has no live vehicle
  /// (schedule-only), fall back to opening the stop. Entering the stop context
  /// (even coming from Nearby) keeps the followed vehicle refreshed by the 30s
  /// poll so it doesn't freeze; but the return target stays the pre-follow
  /// viewport (we didn't arrive through the stop sheet), so closing goes back to
  /// Nearby, not into the stop.
  Future<void> _focusNearbyVehicle(NearbyGroup group) async {
    _clearSearch();
    // A schedule-only row opens the stop without a fetch (its own status says so).
    final hasLiveEta = group.arrivals.any((e) => !e.isScheduled);
    if (!hasLiveEta) {
      _openStopById(group.stopId, stopName: group.stopName, source: Ev.srcNearby);
      return;
    }
    ArrivalsBoard board;
    try {
      board = await ref.read(arrivalsProvider(group.stopId).future);
    } catch (_) {
      _openStopById(group.stopId, stopName: group.stopName, source: Ev.srcNearby);
      return;
    }
    if (!mounted) return;
    // Resolve the live vehicle the row is about (nearbyFollowTarget honours the
    // group status and the board's reality); null → open the stop, never follow a
    // scheduled/absent vehicle.
    final match = nearbyFollowTarget(group, board.arrivals);
    if (match == null) {
      _openStopById(group.stopId, stopName: group.stopName, source: Ev.srcNearby);
      return;
    }
    if (_onDemand) _enterStopContext(group.stopId); // keep the vehicle refreshed
    _focusVehicleFromArrival(match, board.updatedAt, source: Ev.srcNearby);
    _returnToStopId = null; // came from Nearby → close returns to the viewport
  }

  /// Shared stop-opening path (pin tap, Nearby row, or returning to a stop
  /// context after a follow). Seamless (A1): overlays the arrivals on the same
  /// map. When on-demand, entering stop context makes that stop's arrivals the
  /// map's markers (state B); closing the sheet (unless a vehicle was tapped)
  /// clears them back to A.
  void _openStopById(
    String stopId, {
    String? stopName,
    ll.LatLng? at,
    String? source,
    ({String id, String? name})? backTo,
  }) {
    // Entering a stop context while collapsed re-expands the panel (A#4).
    _expandPanelIfCollapsed();
    // `source` non-null marks a fresh user-initiated open (pin / nearby / search
    // / favorites) — logged here, the single funnel for every such entry. The
    // internal return-to-stop after a follow passes no source, so it isn't
    // counted as a new product entry.
    if (source != null) {
      ref.read(eventLoggerProvider).log(Ev.stopOpen, props: {'source': source});
    }
    _clearSearch();
    // Snapshot the viewport before the stop is panned up, so closing the sheet
    // returns here — symmetric to the open. Only the first open of a session
    // captures it (a return-to-stop re-open must not overwrite the origin).
    if (_preStopCameraCenter == null) {
      final cam = _controller?.getCamera();
      if (cam != null) {
        _preStopCameraCenter = cam.center;
        _preStopCameraZoom = cam.zoom;
      }
    }
    if (_onDemand) _enterStopContext(stopId);
    // Shift the stop up into the visible strip ABOVE the sheet, so it isn't
    // hidden under it (and so returning from a follow lands on a visible stop).
    _bringStopIntoView(stopId, at);
    // Desktop panel active: the stop view lives in the persistent panel, NOT a
    // modal — advance the shared state machine instead. On mobile / flag OFF we
    // fall through to the legacy modal (prod behaviour, untouched).
    if (_panelActive) {
      ref.read(openStopNameProvider.notifier).state = stopName;
      _setState(() {
        _slotStopId = stopId;
        _slotStopName = stopName;
        _slotModel = null; // opening a fresh stop clears any leaf model view
      });
      return;
    }
    // Hide the bottom UI (Nearby panel / search) while the sheet is up so they
    // don't overlap (#7).
    _setState(() => _stopSheetOpen = true);
    final seq = ++_stopSheetSeq;
    _currentStop = (id: stopId, name: stopName);
    ref.read(openStopNameProvider.notifier).state = stopName;
    showStopSheet(
      context,
      stopId: stopId,
      stopName: stopName,
      // Redraw the menu button over the scrim so the menu opens over the open
      // stop in one tap (the stop stays underneath).
      onOpenMenu: widget.onOpenDrawer,
      backToName: backTo == null ? null : (backTo.name ?? ''),
      onBack: backTo == null
          ? null
          : () => _switchToStop(backTo.id, backTo.name, withBack: false),
      // Open at the nearby sheet's current height so nearby → stop is a
      // continuous detent, not a jump (owner acceptance #3). `_mobileSheetPx`
      // still holds the nearby height here (reset on the next build).
      initialSize: _mobileSheetPx > 0
          ? _mobileSheetPx / MediaQuery.sizeOf(context).height
          : null,
      // Feed the stop sheet's live height to the geometry owner so the map
      // shifts up to keep the stop above the sheet — same wiring as the nearby
      // sheet (owner R2 #3, regression fix). Without this the geometry owner
      // treats the stop modal as a zero bottom inset and the stop lands under it.
      onHeightChanged: _setMobileSheetPx,
      // Tapping a vehicle row hands the whole arrival to the map so it builds a
      // guaranteed marker, highlights the route and follows (§C).
      onFocusVehicle: (a, asOf) => _focusVehicleFromArrival(a, asOf, source: Ev.srcSheet),
    ).then((_) {
      // Swapped for another stop: the newer sheet owns the state now.
      if (seq != _stopSheetSeq) return;
      _currentStop = null;
      if (mounted) ref.read(openStopNameProvider.notifier).state = null;
      // The stop modal is gone — clear its bottom inset so the geometry owner
      // doesn't keep a phantom one (the nearby sheet re-feeds its own on return).
      _setMobileSheetPx(0);
      if (mounted) _setState(() => _stopSheetOpen = false);
      _onStopSheetClosed(stopId);
    });
  }

  /// Pan [stopId] into the strip of map visible above the arrivals sheet (the
  /// sheet covers the lower ~half), zooming in to at least the individual-stop
  /// level. Resolves the coordinate from the tap ([at]) or the GTFS mirror.
  Future<void> _bringStopIntoView(String stopId, ll.LatLng? at) async {
    final pos = at ?? await _resolveStopLatLng(stopId);
    if (pos == null || !mounted) return;
    final controller = _controller;
    if (controller == null) return;
    final zoom = math.max(controller.getCamera().zoom, _individualZoom);
    // The geometry padding ([_mapInsets]) centres the stop in the visible area —
    // right of the panel on desktop, above the sheet on mobile.
    _camEase(Geographic(lon: pos.longitude, lat: pos.latitude), zoom: zoom);
  }

  /// Synchronous stop → coords from whatever is already loaded (area stops /
  /// focus stops); null if not in hand. Used to anchor the worded route's
  /// "your stop" without an await.
  ll.LatLng? _resolveStopLatLngSync(String stopId) {
    final s = _stopById(stopId);
    return s == null ? null : ll.LatLng(s.lat, s.lon);
  }

  Future<ll.LatLng?> _resolveStopLatLng(String stopId) async {
    final known = _stopById(stopId);
    if (known != null) return ll.LatLng(known.lat, known.lon);
    try {
      final stop = await ref.read(stopLocationProvider(stopId).future);
      if (stop != null) return ll.LatLng(stop.lat, stop.lon);
    } catch (_) {}
    return null;
  }

  /// The stop sheet was dismissed. If a vehicle from this stop is now being
  /// followed, keep the stop context alive so closing the line panel can return
  /// to it; otherwise leave state B for A.
  /// Open [stopId] in place of the stop that's open now (My stops, "Back to …"):
  /// the current sheet is dismissed without its close cleanup and the new stop
  /// opens on the same map, at the same sheet height. With [withBack] the new
  /// sheet offers a one-step link back to the stop that was open.
  void _switchToStop(String stopId, String? stopName, {bool withBack = true}) {
    final previous = _currentStop;
    if (_stopSheetOpen && !_panelActive) {
      Navigator.of(context).pop();
    }
    _openStopById(
      stopId,
      stopName: stopName,
      source: withBack ? Ev.srcFavorites : null,
      backTo: withBack && previous != null && previous.id != stopId ? previous : null,
    );
  }

  void _onStopSheetClosed(String stopId) {
    // A vehicle context is now active (a row was tapped): it owns the camera and
    // will return to the origin later — don't restore here, and keep the stop
    // context alive if we'll come back to it.
    final vehicleContextActive = _following || _focus != null;
    if (_onDemand &&
        _stopContextId == stopId &&
        !(vehicleContextActive && _returnToStopId == stopId)) {
      _exitStopContext();
    }
    if (vehicleContextActive) return;
    _restorePreStopCamera();
  }

  /// Ease the camera back to where it sat before the stop sheet panned it up —
  /// symmetric to the open (same glide), and resetting the sheet's bottom padding
  /// so it doesn't land offset.
  void _restorePreStopCamera() {
    final center = _preStopCameraCenter;
    if (center != null) {
      _camEase(center, zoom: _preStopCameraZoom);
    }
    _preStopCameraCenter = null;
    _preStopCameraZoom = null;
  }

  bool _isLinePinned(String line) {
    final pinned =
        ref.watch(pinnedLinesControllerProvider).valueOrNull ??
        const <PinnedLine>[];
    return pinned.any((l) => l.line == line);
  }

  void _togglePinLine(LineInfo line) {
    final notifier = ref.read(pinnedLinesControllerProvider.notifier);
    final pinned =
        ref.read(pinnedLinesControllerProvider).valueOrNull ??
        const <PinnedLine>[];
    if (pinned.any((l) => l.line == line.line)) {
      notifier.remove(line.line);
    } else {
      notifier.add(
        PinnedLine(
          line: line.line,
          vehicleType: line.vehicleType,
          origin: line.origin,
          destination: line.destination,
        ),
      );
    }
  }

  Future<void> _openLine(LineInfo line) async {
    // Fetch by the entry's route/direction key, not by number, so the exact
    // direction the user tapped in the results opens (F8).
    final shape = await ref
        .read(linesRepositoryProvider)
        .getShapeByRouteId(line.routeId);
    if (!mounted) return;
    _clearSearch();
    final routeStops = shape.stops
        .map(
          (s) => Stop(
            stopId: s.stopId,
            name: s.name,
            lat: s.lat,
            lon: s.lon,
            lines: [line.line],
          ),
        )
        .toList();
    context.push(
      '/map',
      extra: MapScreenArgs(
        stops: routeStops,
        polyline: shape.polyline,
        title: '${line.line}: ${shape.origin} → ${shape.destination}',
        lineNumber: line.line,
      ),
    );
  }

  Future<void> _openPlace(GeocodeResult place) async {
    final center = Geographic(lon: place.lon, lat: place.lat);
    if (!mounted) return;
    _clearSearch();
    _setState(() {
      _pinnedPlace = center;
    });
    _pushStopSources(); // show the pinned-place marker
    _camEase(center, zoom: 16); // centre in the visible area (geometry-aware)
  }
}
