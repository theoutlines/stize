part of '../home_map_screen.dart';

extension _MapPanels on _HomeMapScreenState {
  // ---- Context panel (desktop-only) rendering ------------------------------

  List<Widget> _contextSlot(
    AppLocalizations l10n,
    ThemeData theme, {
    required Size size,
  }) {
    final panelW = panelWidthFor(size.width);
    final collapsed = _panelCollapsed;

    // The global search is a PERSISTENT element above the panel body (owner
    // A#6 + decision #6): it stays put and visible whether the panel is open or
    // collapsed, so it lives OUTSIDE the collapsing body. The body (nav +
    // content) is what slides away.
    // Google-Maps "islands": the search row (burger + pill, each its OWN
    // floating backdrop — no shared container, owner R2 #1) and the panel body
    // island, inset from the edges with a SMALL gap between them (R2 #2).
    const inset = kPanelIslandInset;
    const searchToPanelGap = _HomeMapScreenState._kIslandGap;
    final searchCard = PointerInterceptor(
      child: _panelSearchField(l10n, theme),
    );

    final body = ContextPanel(
      width: panelW,
      searchField: null, // search is hoisted above (searchCard); see above
      navRow: _slotNavRow(l10n),
      borderRadius: BorderRadius.circular(16), // island corners
      hug: true,
      child: _searching ? _searchResultsList(l10n) : _slotContent(l10n),
    );

    final widgets = <Widget>[
      // Left region: the persistent search island on top, a gap, then the
      // collapsible panel island — both inset from the screen edges.
      Positioned.fill(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(
              left: inset,
              top: inset,
              bottom: inset,
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: panelW,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchCard,
                    const SizedBox(height: searchToPanelGap),
                    // The panel island slides fully off the left screen edge when
                    // collapsed (offset > 1 ⇒ entirely past x=0 ⇒ "fully hidden",
                    // A#2), leaving only the search island. No ClipRect, so the
                    // island keeps its drop shadow toward the map.
                    Flexible(
                      child: AnimatedSlide(
                        duration: _HomeMapScreenState._panelCollapseDuration,
                        curve: _HomeMapScreenState._panelCollapseCurve,
                        offset: collapsed ? const Offset(-1.3, 0) : Offset.zero,
                        child: body,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ];
    if (_followLost) widgets.add(_backToVehiclePill(l10n, theme, size: size));
    return widgets;
  }

  /// Title of a level, for its own header and for the back link of the level
  /// above it.
  String _levelTitle(_SlotLevel level, AppLocalizations l10n) =>
      switch (level) {
        _StopLevel(:final id, :final name) =>
          ref.watch(stopLocationProvider(id)).valueOrNull?.name ?? name ?? '',
        _MyStopsLevel() => l10n.navMyStops,
        _SettingsLevel() => l10n.settingsTitle,
        _FeedbackLevel(:final form) =>
          form ? l10n.feedbackFormTitle : l10n.drawerFeedbackSheetTitle,
        _GuideLevel(:final page) => switch (page) {
          GuidePage.home => l10n.guideTitle,
          GuidePage.readStop => l10n.guideReadStop,
          GuidePage.places => l10n.guidePlaces,
        },
      };

  /// The header of the current level; null on Nearby (root). One control per
  /// level: a "← `previous`" back link when there is a previous level, else a ×
  /// that closes back to Nearby. Same on the mobile sheet and the desktop panel.
  /// The model leaf takes precedence; the vehicle view keeps its line row.
  Widget? _slotNavRow(AppLocalizations l10n) {
    final model = _slotModel;
    if (model != null) {
      return LevelHeader(
        title: model.fleet.modelName ?? l10n.fleetUnknownModel,
        backLabel: _levels.isEmpty
            ? l10n.followingVehicle
            : _levelTitle(_levels.last, l10n),
        onBack: _slotBack,
      );
    }
    switch (_activeView) {
      case ContextView.nearby:
        return null;
      case ContextView.stop:
      case ContextView.myStops:
      case ContextView.guide:
      case ContextView.settings:
      case ContextView.feedback:
        final top = _levels.last;
        final title = _levelTitle(top, l10n);
        return LevelHeader(
          title: title,
          backLabel: _levels.length > 1
              ? _levelTitle(_levels[_levels.length - 2], l10n)
              : null,
          onBack: _slotBack,
          // Mobile: the close rides above the sheet (MapSheetCloseButton).
          onClose: _panelActive ? _closeAllLevels : null,
          trailing: top is _StopLevel
              ? StopHeaderActions(stopId: top.id, stopName: title)
              : null,
        );
      case ContextView.vehicle:
        return _followHeader(l10n);
    }
  }

  /// The active level's content (no header — the level header owns the title).
  /// [scrollController] is the mobile sheet's, so dragging the content drags
  /// the sheet; null on the desktop panel.
  Widget _slotContent(
    AppLocalizations l10n, {
    ScrollController? scrollController,
  }) {
    final model = _slotModel;
    if (model != null) {
      return FleetModelView(
        showTitle: false,
        fleet: model.fleet,
        fallbackType: model.type,
        garageNo: model.garageNo,
        scrollController: scrollController,
      );
    }
    switch (_activeView) {
      case ContextView.nearby:
        return NearbyView(
          userLocation: _browsePoint ?? _meTo,
          locationDenied: _locationDenied,
          active: _tabActive && _appResumed,
          onEnableLocation: _recenterOnMe,
          onTapGroup: _focusNearbyVehicle,
          // The persistent global search above the panel replaces the local
          // "filter lines nearby" field (decision #6).
          showLocalSearch: false,
          hugContent: true,
          banner: _guideBanner(l10n),
        );
      case ContextView.settings:
        return StretchCardList(
          controller: scrollController,
          // Desktop panel (no sheet controller): hug the two settings rows
          // instead of stretching to the window height.
          shrinkWrap: scrollController == null,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: const [SettingsPanel()],
        );
      case ContextView.feedback:
        final fb = _levels.last as _FeedbackLevel;
        if (fb.form) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.only(top: 8),
            child: FeedbackForm(showTitle: false, onSent: _popLevel),
          );
        }
        final formEnabled = ref.watch(feedbackFormEnabledProvider);
        return StretchCardList(
          controller: scrollController,
          shrinkWrap: scrollController == null,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (formEnabled)
              GuideRow(
                icon: StizeIcons.edit,
                title: l10n.feedbackWriteToMe,
                subtitle: l10n.feedbackWriteToMeSubtitle,
                onTap: () => _pushLevel(const _FeedbackLevel(form: true)),
              ),
            GuideRow(
              icon: StizeIcons.bug,
              title: l10n.feedbackGithubIssues,
              subtitle: l10n.feedbackGithubIssuesSubtitle,
              onTap: () => openExternalUrl(kRepoIssuesUrl),
            ),
          ],
        );
      case ContextView.guide:
        final page = (_levels.last as _GuideLevel).page;
        void openStop(String id, String name) =>
            _openStopById(id, stopName: name, source: Ev.srcGuide);
        return switch (page) {
          GuidePage.home => GuideHome(
            scrollController: scrollController,
            onOpenPage: _openGuideLevel,
            onOpenStop: openStop,
          ),
          GuidePage.readStop => GuideReadStop(
            scrollController: scrollController,
          ),
          GuidePage.places => GuidePlaces(
            scrollController: scrollController,
            onOpenStop: openStop,
          ),
        };
      case ContextView.myStops:
        return MyStopsList(
          scrollController: scrollController,
          onTapStop: (id, name) =>
              _openStopById(id, stopName: name, source: Ev.srcFavorites),
        );
      case ContextView.stop:
        return StopBoard(
          key: ValueKey('slot-stop-$_slotStopId'),
          stopId: _slotStopId!,
          initialStopName: _slotStopName,
          scrollController: scrollController,
          // The level header above owns the title + star; the board is body-only.
          showHeader: false,
          onFocusVehicle: (a, asOf) =>
              _focusVehicleFromArrival(a, asOf, source: Ev.srcSheet),
          // A row's Fleet badge opens the model INSIDE the slot (no modal).
          onOpenFleetCard: (fleet, garageNo, type) =>
              _openSlotModel(fleet, garageNo: garageNo, type: type),
        );
      case ContextView.vehicle:
        final track = _selectedVehicleKey == null
            ? null
            : _vehAnimator.trackFor(_selectedVehicleKey!);
        final line = _focus?.line ?? track?.line ?? '';
        final type = _focus?.type ?? track?.type ?? VehicleType.bus;
        final f = _followModel(l10n);
        return VehicleView(
          line: line,
          type: type,
          scheduled:
              _focus?.scheduled ?? (track?.source == VehicleSource.scheduled),
          garageNo: _selectedVehicleKey,
          route: f.route,
          vehicleBetween: f.between,
          stuckMinutes: f.stuckMinutes,
          // A line with no route geometry in our GTFS (e.g. "Ada 4"): an honest
          // note instead of an empty route list (owner R4 #2).
          routeUnavailable: _followNoRouteData,
          // Warn only if a jam is on this vehicle's direction AND ahead of it.
          jamAhead: _jamAheadForFollowed(track),
          scrollController: scrollController,
        );
    }
  }

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
    final board = _followBoardStopId == null
        ? null
        : ref.watch(arrivalsProvider(_followBoardStopId!)).valueOrNull;
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
    final id = _followBoardStopId;
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
  ({
    List<FollowRouteStop> route,
    bool between,
    int? stuckMinutes,
    int? eta,
    String? caption,
  })
  _followModel(AppLocalizations l10n) {
    final upcoming = _buildUpcomingStops();
    final key = _selectedVehicleKey;
    int? stuckMinutes;
    if (key != null && _vehAnimator.isStuck(key)) {
      final still = _vehAnimator.stillFor(key);
      if (still != null) stuckMinutes = stuckMinutesOf(still);
    }
    final focus = _focus;
    final route = <FollowRouteStop>[];
    var between = false;
    if (upcoming.isNotEmpty && focus != null) {
      final seq = upcoming.first.stop.seq;
      final atStop = upcoming.first.vehicleHere;
      final hasPassed = seq > 0 && seq - 1 < focus.stops.length;
      if (hasPassed) {
        route.add(
          FollowRouteStop(name: focus.stops[seq - 1].name, passed: true),
        );
      }
      between = hasPassed && !atStop;
      final shown = upcoming.take(8).toList();
      for (var i = 0; i < shown.length; i++) {
        final u = shown[i];
        route.add(
          FollowRouteStop(
            name: u.stop.name,
            etaMinutes: u.etaMinutes,
            yours: u.isBoardStop,
            vehicleHere: i == 0 && !between,
          ),
        );
      }
    }

    int? eta;
    String? caption;
    final boardIdx = upcoming.indexWhere((u) => u.isBoardStop);
    if (boardIdx >= 0) {
      final u = upcoming[boardIdx];
      eta = u.etaMinutes;
      caption = boardIdx == 0 && u.vehicleHere
          ? l10n.followAtStop(u.stop.name)
          : l10n.followStopsTo(boardIdx + 1, u.stop.name);
    } else if (upcoming.isNotEmpty) {
      eta = upcoming.first.etaMinutes;
      caption = l10n.followNextStop(upcoming.first.stop.name);
    }
    return (
      route: route,
      between: between,
      stuckMinutes: stuckMinutes,
      eta: eta,
      caption: caption,
    );
  }

  /// Build the followed vehicle's upcoming-stop list (owner R1 #5) from the
  /// focused route shape + the marker's live position, anchored to the arrival's
  /// own ETA when known. Empty when there's no shape yet.
  List<UpcomingStop> _buildUpcomingStops() {
    final focus = _focus;
    final key = _selectedVehicleKey;
    if (focus == null || key == null || focus.stops.isEmpty) {
      _routeAheadDiag = _followNoRouteData
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
      boardStop: _followBoardStop ?? vehicle,
      stopsRemaining: _followStopsRemaining,
      etaToBoardMinutes: _followEtaMinutes,
    );
    // Progress diagnostic (owner R4 #1): how many stops still ahead and which is
    // next. As the vehicle passes a stop these change — the proof the list
    // slides with live progress, not a frozen entry snapshot.
    _routeAheadDiag =
        'ROUTE ahead ${plan.stops.length} next ${plan.nextStop?.name ?? "-"}';
    return plan.stops;
  }

  Widget _panelSearchField(AppLocalizations l10n, ThemeData theme) {
    // The burger lives in the search row on the nearby root — and, while
    // collapsed, in EVERY view: the context nav row (its usual back/drawer
    // chrome) is slid away, so the persistent search is the only place left to
    // reach the drawer (owner A#2: burger reachable in both states).
    final showBurger =
        _panelCollapsed ||
        (_slotModel == null && _activeView == ContextView.nearby);
    // Owner R2 #1: no shared container behind the row — the burger is its OWN
    // round button with its own backdrop, the search is its OWN floating pill.
    return Row(
      children: [
        if (showBurger) ...[
          Material(
            color: theme.colorScheme.surface,
            elevation: 3,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              icon: const Icon(StizeIcons.menu),
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
              onPressed: widget.onOpenDrawer,
            ),
          ),
          const SizedBox(width: 8),
        ],
        // The same pill as on mobile (owner, 2026-11-25): locate | where the
        // list is | search. A tap turns it into the field.
        Expanded(
          child: MapSearchPill(
            controller: _searchController,
            focusNode: _focusNode,
            active: _deskSearchActive || _searching,
            placeLabel: _browsePlaceLabel(l10n),
            away: _browsePoint != null,
            onLocate: _recenterOnMe,
            onChanged: _onSearchChanged,
            onActivate: () => _setState(() => _deskSearchActive = true),
            onClose: () {
              _clearSearch();
              _setState(() => _deskSearchActive = false);
            },
          ),
        ),
      ],
    );
  }

  /// The "Back to vehicle" pill, pinned to the bottom of the VISIBLE map area
  /// (right of the panel) with an off-screen hint. Decision #8, desktop-only.
  Widget _backToVehiclePill(
    AppLocalizations l10n,
    ThemeData theme, {
    required Size size,
  }) {
    final track = _selectedVehicleKey == null
        ? null
        : _vehAnimator.trackFor(_selectedVehicleKey!);
    final line = _focus?.line ?? track?.line ?? '';
    final leftInset = panelWidthFor(size.width);
    return Positioned(
      left: leftInset,
      right: 0,
      bottom: 16,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (line.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    l10n.vehicleOffScreen(line),
                    style: StizeText.of(context).control,
                  ),
                ),
              BackToVehiclePill(
                line: line,
                onTap: _resumeFollowFromPill,
                arrowTurns: _offScreenArrowTurns(size),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Turns (0..1) for the off-screen direction arrow toward the followed marker,
  /// or null when it's on-screen. [StizeIcons.nearMe] points up at 0.
  double? _offScreenArrowTurns(Size size) {
    final key = _selectedVehicleKey;
    final controller = _controller;
    if (key == null || controller == null) return null;
    if (_vehAnimator.trackFor(key) == null) return null;
    try {
      final pos = _vehAnimator.positionOf(key, _vehAnim.value);
      final screen = controller.toScreenLocation(
        Geographic(lon: pos.longitude, lat: pos.latitude),
      );
      final dx = screen.dx - size.width / 2;
      final dy = screen.dy - size.height / 2;
      if (dx.abs() < size.width / 2 && dy.abs() < size.height / 2) return null;
      // Rotation from "up" (north) toward (dx, dy).
      return math.atan2(dx, -dy) / (2 * math.pi);
    } catch (_) {
      return null;
    }
  }

  /// True for one of the imperative stop layers — the ambient `stg-stops-*`
  /// set AND the focused-line `stg-focus-*` layers. The focus layers were
  /// silently excluded here, so the render diagnostics (GL-layers list +
  /// `renders`) never saw the focused-line stop pins at all — exactly the
  /// layer whose pins go missing during follow.
  static bool _isStopLayer(String id) =>
      id.startsWith('stg-stops-') || id.startsWith('stg-focus-');

  /// Short label for a stop layer id in diagnostics ('stg-stops-bus' → 'bus',
  /// 'stg-focus-stops' → 'focus-stops').
  String _glLayerLabel(String id) => id.startsWith('stg-stops-')
      ? id.substring('stg-stops-'.length)
      : id.startsWith('stg-')
      ? id.substring('stg-'.length)
      : id;

  /// Staging-only render-diagnostics overlay (`isStaging`, invisible in prod).
  /// On Flutter-CanvasKit the map/layers aren't in the DOM and external JS
  /// inspection is blind, so this is the one reliable window into the stop-render
  /// pipeline: the gate flags ([_imagesReady]/[_stopLayersAdded]/style), where
  /// the last viewport fetch landed, how many stops came back and how they split
  /// across the marker lists, which imperative stop layers are actually on the
  /// map, and — via [MapController.queryLayers] — whether each type's layer
  /// really draws at a real stop's pixel (catches "layer present, data pushed,
  /// but nothing rendered"). Keep it: it is what broke the multi-round
  /// stop-render investigation open.
  Widget _stopDiagnosticsOverlay(ThemeData theme) {
    final key = _selectedVehicleKey;
    final timed = key == null ? null : _vehAnimator.trackFor(key)?.timed;
    final now = DateTime.now();
    final center = _lastFetchCenter;
    final controller = _controller;
    final style = _style;

    // How many of a layer's stops actually draw, counted over EVERY on-screen
    // stop — not just the first. The old check sampled `pts.first`, which is
    // usually under this panel (top-left) or off the edge, so it read MISS even
    // while pins drew: a false alarm we both chased. 'drawn/onscreen': `bus:0/6`
    // = six bus stops in view, NONE drew (a real miss); `bus:6/6` = all drew;
    // `bus:-` = no such stops; `bus:0/0offscr` = none currently in view.
    final screen = MediaQuery.sizeOf(context);
    String renderStats(String label, Iterable<({double lat, double lon})> pts) {
      final list = pts.toList();
      if (list.isEmpty) return '$label:-';
      if (controller == null) return '$label:?';
      var onscreen = 0, drawn = 0;
      for (final p in list) {
        try {
          final o = controller.toScreenLocation(
            Geographic(lon: p.lon, lat: p.lat),
          );
          if (o.dx < 0 ||
              o.dy < 0 ||
              o.dx > screen.width ||
              o.dy > screen.height) {
            continue; // off the visible map — a query there is meaningless
          }
          onscreen++;
          if (controller.queryLayers(o).any((q) => _isStopLayer(q.layerId))) {
            drawn++;
          }
        } catch (_) {}
      }
      return onscreen == 0 ? '$label:0/0offscr' : '$label:$drawn/$onscreen';
    }

    ({double lat, double lon}) fromFeature(Feature<Point> f) =>
        (lat: f.geometry!.position.y, lon: f.geometry!.position.x);

    // The imperative stop layers actually on the map right now (should be 8).
    // `getLayerIds` is the only style read that surfaces them; guard hard.
    var glLayers = 'style=null';
    if (style != null) {
      try {
        // ignore: invalid_use_of_visible_for_testing_member
        final allIds = style.getLayerIds();
        final ids = allIds.where(_isStopLayer).map(_glLayerLabel).toList();
        glLayers = ids.isEmpty ? 'NONE' : ids.join(' ');
      } catch (_) {
        glLayers = 'err';
      }
    }

    final lines = <String>[
      'STOP DIAGNOSTICS (staging)',
      'zoom ${_currentZoom.toStringAsFixed(2)}  minStops $_minStopsZoom  indiv $_individualZoom',
      // The gates that decide whether ANY stop layer is built/drawn.
      'imagesReady $_imagesReady  stopLayers $_stopLayersAdded  style ${style != null}  focus ${_focus != null}',
      center == null
          ? 'last fetch: none yet (zoom < $_minStopsZoom?)'
          : 'fetch @ ${center.latitude.toStringAsFixed(5)},${center.longitude.toStringAsFixed(5)} r=${_lastFetchRadius.toStringAsFixed(0)}m',
      'returned ${_areaStops.length} stops (cap 50)',
      'markers: bus ${_busPts.length} tram ${_tramPts.length} '
          'trolley ${_trolleyPts.length} mixed ${_mixedPts.length} '
          'cluster ${_clusterPts.length}',
      'GL layers on map: $glLayers',
      // How many stops of each ambient type actually draw, over ALL on-screen
      // stops. During follow the ambient sources are emptied on purpose, so
      // these read `-`/`0/0` — look at the FOCUS render line below instead.
      'renders: ${renderStats('bus', _busPts.map(fromFeature))} '
          '${renderStats('tram', _tramPts.map(fromFeature))} '
          '${renderStats('trolley', _trolleyPts.map(fromFeature))} '
          '${renderStats('mixed', _mixedPts.map(fromFeature))}',
      // Geometry owner: the padding EVERY camera move actually sends to maplibre
      // (owner R3 #1 — prove the panel-aware inset reaches the map).
      'GEO panelActive $_panelActive sheetPx ${_mobileSheetPx.toStringAsFixed(0)} '
          'insets L${_mapInsets.left.toStringAsFixed(0)} B${_mapInsets.bottom.toStringAsFixed(0)}',
      // Follow camera: marker pixel vs visible-area-centre target + camera centre
      // (owner R3 #1 — prove vertical tracking).
      _followCamDiag,
      _routeAheadDiag,
      // Vehicle-animation state (on-demand context / follow diagnosis).
      'VEH onDemand $_onDemand stopCtx ${_stopContextId ?? "-"} '
          'following $_following sel ${_selectedVehicleKey ?? "-"}',
      'VEH tracks ${_vehAnimator.tracks.length} '
          'timed ${_vehAnimator.tracks.values.where((t) => t.timed != null).length} '
          'movingNow ${_vehAnimator.tracks.keys.where(_vehAnimator.hasMotion).length} '
          'pending ${_vehAnimator.hasPendingMotion}',
      // `animV` used to sit here. It's the legacy ease controller's progress,
      // which only moves markers that have NO timing plan — so next to `timed
      // N` it reads as a symptom ("the animation is stuck at 0") while being
      // simply unused. Dropped; `plan`/`vel` below is the real motion read-out.
      'VEH ticker ${_vehTicker?.isActive ?? false} '
          'paused $_paused refreshTicks $_refreshTicks pumps $_pumpCount',
      'VEH lastCtx ageSec ${_lastCtxBoardAgeSec ?? "-"} '
          'live $_lastCtxLive withTraj $_lastCtxWithTraj',
      // Catch-up instrumentation for the followed vehicle: how far behind the
      // plan's predicted-now spot the marker is (gap) and how fast it's moving
      // to close it (vel). A smooth catch-up shows the gap easing to ~0 with vel
      // ramping up then settling to the plan speed — never a spike then a crawl.
      catchUpDiagLine(timed, now),
      dwellDiagLine(timed),
      stopCauseDiagLine(timed, now),
      'FOCUS layersAdded $_focusLayersAdded stops ${_focus?.stops.length ?? 0} '
          'err ${_focusLayerError ?? "-"}',
      // The real test for the followed line's stop pins: of the focus stops in
      // view, how many actually draw. `focus:0/8` with layersAdded true + err -
      // = layer & source are fine but nothing paints (image not resolved for the
      // layer, or z-order); `focus:8/8` = pins ARE there (trust this over eyes).
      'FOCUS render ${renderStats('focus', (_focus?.stops ?? const <Stop>[]).map((s) => (lat: s.lat, lon: s.lon)))}',
      boardAgeDiagLine(_boardAgePolls),
      fixAgeDiagLine(_vehAnimator.fixAgeStats()),
    ];

    return DiagnosticsOverlay(
      lines: lines,
      bottomMargin: _panelActive
          ? 12
          : _mobileSheetPx + (_oneScrollRoot ? MapSearchPill.height + 32 : 8),
    );
  }

  Widget _focusPanel() {
    // The follow bar must appear the instant follow starts, from ANY source —
    // not only once the route shape has loaded (async, and it sets `_focus`).
    // A follow entered from the persistent Nearby sheet used to leave `_focus`
    // null until the shape landed, so the bar (and its × exit) never showed and
    // the user was trapped. So derive the badge from the focused line when it's
    // loaded, otherwise from the followed vehicle's own track.
    final focus = _focus;
    final key = _selectedVehicleKey;
    final track = key == null ? null : _vehAnimator.trackFor(key);
    final line = focus?.line ?? track?.line ?? '';
    final type = focus?.type ?? track?.type ?? VehicleType.bus;
    final subtitle = focus != null
        ? '${focus.origin} → ${focus.destination}'
        : null;
    return FollowBar(
      line: line,
      type: type,
      subtitle: subtitle,
      scheduled: focus?.scheduled ?? false,
      onClose: _closeVehicleContext,
    );
  }

  // Zoom +/- buttons make sense only with a mouse: show them on desktop
  // browsers. On the native mobile apps and mobile web, pinch/double-tap
  // gestures handle zoom, so they'd just be clutter.
  bool get _showZoomControls {
    if (!kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      default:
        return false;
    }
  }

  void _zoomBy(double delta) {
    final controller = _controller;
    if (controller == null) return;
    final camera = controller.getCamera();
    // Carry the geometry padding so a zoom doesn't reset it (which would jump
    // the focus back under the panel).
    _camEase(
      camera.center,
      zoom: (camera.zoom + delta).clamp(kCityMinZoom, kCityMaxZoom),
    );
  }

  Widget _topButtons(ThemeData theme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // The desktop panel carries its own burger in the persistent search
            // row (visible whether open or collapsed), so suppress this floating
            // one whenever the panel is active — otherwise a collapsed panel
            // would show two burgers. Keep the right-hand controls in place.
            if (_panelActive)
              const SizedBox.shrink()
            else
              MapRoundButton(
                icon: StizeIcons.menu,
                tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
                onTap: widget.onOpenDrawer,
              ),
            Column(
              // Measured by the one-scroll pill (its bottom is where the pill
              // starts pushing the buttons up).
              key: _topButtonsKey,
              mainAxisSize: MainAxisSize.min,
              // Right-aligned so the one-time label beside the transport
              // toggle grows to the left and the buttons stay in one column.
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Jam-mode toggle: shows ONLY while the city has active jams; a
                // toggle of the same map (fit to all jams / back), with a red count
                // badge. No jams → not in the tree at all.
                _jamModeButton(),
                // Hides itself — gap and all — while the flag is off, so the
                // killswitch leaves this stack exactly as production has it.
                const VehicleModeToggle(),
                // "Where am I" lives in the search pill only, on mobile
                // (owner, 2026-11-23) and on desktop, whose panel carries the
                // same pill since 2026-11-25: no second round button here.
                if (_showZoomControls) ...[
                  const SizedBox(height: 12),
                  MapZoomControl(
                    onZoomIn: () => _zoomBy(1),
                    onZoomOut: () => _zoomBy(-1),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
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
      if (_jamModeOn) {
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
      on: _jamModeOn,
      relevantCount: relevant,
      onToggle: () => _setJamMode(!_jamModeOn),
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
    if (_jamModeOn == on) return;
    _setState(() => _jamModeOn = on);
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

  /// (Re)build the focused-line layers imperatively: the route line (in its type
  /// colour) and that line's own stops, both inserted *below* the vehicle badge
  /// so the followed coin stays on top. Removes them when there's no focus. The
  /// route layer is recreated per focus because its colour is baked into the
  /// layer paint. Best-effort: a failure just leaves the route un-highlighted.
  Future<void> _syncFocusLayers() async {
    final style = _style;
    if (style == null) return;
    // Tear down any previous focus layers first (colour/route may have changed).
    if (_focusLayersAdded) {
      for (final id in const [
        _HomeMapScreenState._focusRouteLayerId,
        _HomeMapScreenState._focusStopsLayerId,
      ]) {
        try {
          await style.removeLayer(id);
        } catch (_) {}
        try {
          await style.removeSource(_stopSourceId(id));
        } catch (_) {}
      }
      _focusLayersAdded = false;
    }
    final focus = _focus;
    if (focus == null) return;
    final below = focusInsertBelowLayerId(vehicleLayersAdded: _vehLayerAdded);
    try {
      if (focus.polyline.length >= 2) {
        final srcId = _stopSourceId(_HomeMapScreenState._focusRouteLayerId);
        await style.addSource(
          GeoJsonSource(id: srcId, data: _focusRouteGeoJson(focus)),
        );
        final line = PolylineLayer(
          polylines: const [],
          color: vehicleColor(focus.type),
          width: 5,
        );
        await style.addLayer(
          LineStyleLayer(
            id: _HomeMapScreenState._focusRouteLayerId,
            sourceId: srcId,
            layout: line.getLayout(),
            paint: line.getPaint(),
          ),
          belowLayerId: below,
        );
      }
      final stopsSrc = _stopSourceId(_HomeMapScreenState._focusStopsLayerId);
      await style.addSource(
        GeoJsonSource(id: stopsSrc, data: _focusStopsGeoJson(focus)),
      );
      final pin = MarkerLayer(
        points: const [],
        iconImage: MapImages.forStop(focus.type),
        iconSize: _HomeMapScreenState._iconSize,
        iconAllowOverlap: true,
      );
      await style.addLayer(
        SymbolStyleLayer(
          id: _HomeMapScreenState._focusStopsLayerId,
          sourceId: stopsSrc,
          layout: pin.getLayout(),
          paint: pin.getPaint(),
        ),
        belowLayerId: below,
      );
      _focusLayersAdded = true;
      _focusLayerError = null;
    } catch (e) {
      // Don't swallow silently — a failed focus-stops add is exactly the class
      // of "the route line draws but its stop pins don't" bug. debugPrint is
      // stripped in release web, so surface it on the staging overlay instead
      // (the reliable render-debug channel on Flutter-CanvasKit).
      _focusLayerError = '$e';
      _focusLayersAdded = false;
    }
  }

  String _focusRouteGeoJson(_LineFocus focus) => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          // focus.polyline is [lat, lon]; GeoJSON is [lon, lat].
          'coordinates': [
            for (final p in focus.polyline) [p[1], p[0]],
          ],
        },
        'properties': const <String, dynamic>{},
      },
    ],
  });

  String _focusStopsGeoJson(_LineFocus focus) => jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final s in focus.stops)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [s.lon, s.lat],
          },
          // Only stopId (the tap handler looks the name up) — jsonEncode escapes
          // it correctly regardless, but the name isn't needed here.
          'properties': {'stopId': s.stopId},
        },
    ],
  });
}
