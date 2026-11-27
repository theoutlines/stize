part of '../home_map_screen.dart';

// Follow mode: the follow header and its route list, the vehicles of the same
// line around it, the upcoming stops plan, and camera moves made by the app.

extension _MapFollow on _HomeMapScreenState {
  /// The follow level's head: the vehicle as a card in its line colour. The
  /// close lives in it on the desktop island; on mobile it rides above the
  /// sheet and the card carries the sheet's grabber instead.
  Widget _followHeader(AppLocalizations l10n) {
    final track = _selectedVehicleKey == null
        ? null
        : _vehAnimator.trackFor(_selectedVehicleKey!);
    final line = _focus?.line ?? track?.line ?? '';
    final type = _focus?.type ?? track?.type ?? VehicleType.bus;
    final f = _followModel(l10n);
    final scheduled =
        _focus?.scheduled ?? (track?.source == VehicleSource.scheduled);
    final siblings = _followSiblings(line, track);
    final current = siblings
        .where((a) => VehicleTrackAnimator.keyFor(a) == _selectedVehicleKey)
        .firstOrNull;
    final board = _follow.boardStopId == null
        ? null
        : ref.watch(arrivalsProvider(_follow.boardStopId!)).valueOrNull;
    return FollowHeader(
      line: line,
      type: type,
      destination: _focus?.destination,
      // The same number the board card showed for this vehicle, when the
      // board has it; else the route's estimate.
      etaMinutes: current?.etaMinutes ?? f.eta,
      vehicles: siblings.length < 2 || board == null
          ? const []
          : [
              for (final a in siblings)
                FollowVehicleOption(
                  etaMinutes: a.etaMinutes,
                  selected:
                      VehicleTrackAnimator.keyFor(a) == _selectedVehicleKey,
                  onTap: () => _focusVehicleFromArrival(
                    a,
                    board.updatedAt,
                    source: Ev.srcSheet,
                  ),
                ),
            ],
      caption: f.caption,
      moving:
          _selectedVehicleKey != null && f.stuckMinutes == null && !scheduled,
      approximate: f.stuckMinutes != null,
      onClose: _panelActive ? _closeVehicleContext : null,
      showHandle: !_panelActive,
      topRadius: _panelActive ? 0 : kSheetRadius.topLeft.x,
    );
  }

  /// The live vehicles of the followed line and direction on the board the
  /// follow came from, soonest first, at most three: the head's switcher.
  List<Arrival> _followSiblings(String line, VehicleTrack? track) {
    final id = _follow.boardStopId;
    if (id == null) return const [];
    final board = ref.watch(arrivalsProvider(id)).valueOrNull;
    if (board == null) return const [];
    final dir = track?.directionRouteId;
    final list =
        board.arrivals
            .where(
              (a) =>
                  a.line == line &&
                  arrivalHasLivePosition(a) &&
                  (dir == null || (a.directionRouteId ?? a.routeId) == dir),
            )
            .toList()
          ..sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes));
    return list.take(3).toList();
  }

  /// What the follow header and route show, from the focused shape and the
  /// followed vehicle's live position: the stop behind it, the stops ahead with
  /// their times, your stop, and how long it has stood still.
  FollowModel _followModel(AppLocalizations l10n) {
    final key = _selectedVehicleKey;
    int? stuckMinutes;
    if (key != null && _vehAnimator.isStuck(key)) {
      final still = _vehAnimator.stillFor(key);
      if (still != null) stuckMinutes = stuckMinutesOf(still);
    }
    return buildFollowModel(
      upcoming: _buildUpcomingStops(),
      lineStopNames: _focus?.stops.map((s) => s.name).toList(),
      stuckMinutes: stuckMinutes,
      l10n: l10n,
    );
  }

  /// Build the followed vehicle's upcoming-stop list (owner R1 #5) from the
  /// focused route shape + the marker's live position, anchored to the arrival's
  /// own ETA when known. Empty when there's no shape yet.
  List<UpcomingStop> _buildUpcomingStops() {
    final focus = _focus;
    final key = _selectedVehicleKey;
    if (focus == null || key == null || focus.stops.isEmpty) {
      _diag.routeAhead = _follow.noRouteData
          ? 'ROUTE unavailable (no GTFS geometry for line)'
          : 'ROUTE ahead -';
      return const [];
    }
    final track = _vehAnimator.trackFor(key);
    if (track == null) return const [];
    final vehicle = _vehAnimator.positionOf(key, _vehAnim.value);
    final shape = RouteShape(
      routeId: track.directionRouteId ?? '',
      vehicleType: focus.type,
      origin: focus.origin,
      destination: focus.destination,
      polyline: focus.polyline,
      stops: [
        for (var i = 0; i < focus.stops.length; i++)
          RouteShapeStop(
            stopId: focus.stops[i].stopId,
            name: focus.stops[i].name,
            lat: focus.stops[i].lat,
            lon: focus.stops[i].lon,
            seq: i,
          ),
      ],
    );
    final plan = planVehicleRoute(
      shape: shape,
      vehicle: vehicle,
      boardStop: _follow.boardStop ?? vehicle,
      stopsRemaining: _follow.stopsRemaining,
      etaToBoardMinutes: _follow.etaMinutes,
    );
    // Progress diagnostic (owner R4 #1): how many stops still ahead and which is
    // next. As the vehicle passes a stop these change — the proof the list
    // slides with live progress, not a frozen entry snapshot.
    _diag.routeAhead =
        'ROUTE ahead ${plan.stops.length} next ${plan.nextStop?.name ?? "-"}';
    return plan.stops;
  }

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
      path: _shapes.byLine[shapeKey],
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
