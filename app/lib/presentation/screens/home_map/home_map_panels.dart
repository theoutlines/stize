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
          onClose: _closeAllLevels,
          trailing: top is _StopLevel
              ? StopHeaderActions(stopId: top.id, stopName: title)
              : null,
        );
      case ContextView.vehicle:
        final track = _selectedVehicleKey == null
            ? null
            : _vehAnimator.trackFor(_selectedVehicleKey!);
        final line = _focus?.line ?? track?.line ?? '';
        final type = _focus?.type ?? track?.type ?? VehicleType.bus;
        final dir = (_focus != null)
            ? '${_focus!.origin} → ${_focus!.destination}'
            : l10n.followingVehicle;
        return ContextNavRow(
          onBack: _slotBack,
          leading: _linePill(line, type),
          title: dir,
        );
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
          userLocation: _meTo,
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
        return ListView(
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
        return ListView(
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
        final stuck =
            _selectedVehicleKey != null &&
            _vehAnimator.isStuck(_selectedVehicleKey!);
        return VehicleView(
          line: line,
          type: type,
          origin: _focus?.origin,
          destination: _focus?.destination,
          stuck: stuck,
          scheduled:
              _focus?.scheduled ?? (track?.source == VehicleSource.scheduled),
          garageNo: _selectedVehicleKey,
          upcomingStops: _buildUpcomingStops(),
          // A line with no route geometry in our GTFS (e.g. "Ada 4"): show an
          // honest note instead of an empty route list (owner R4 #2).
          routeUnavailable: _followNoRouteData,
          // Item 5: warn only if a jam is on this vehicle's direction AND ahead of
          // it — opposite direction / a jam already behind stays silent.
          jamAhead: _jamAheadForFollowed(track),
          // The route is drawn on the panel-side map, so no "show route" button.
          showRouteButton: false,
          // Tapping the "About" card opens the model as a leaf IN the panel.
          onOpenModel: (fleet) =>
              _openSlotModel(fleet, garageNo: _selectedVehicleKey, type: type),
        );
    }
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

  /// The compact coloured line pill (in the vehicle nav row).
  Widget _linePill(String line, VehicleType type) {
    final color = vehicleColor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(StizeRadius.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          vehicleGlyph(
            type,
            size: 16,
            color: StizeColors.of(context).onTransit,
          ),
          const SizedBox(width: 8),
          Builder(
            builder: (context) {
              final stize = StizeColors.of(context);
              return Text(
                line,
                style: StizeType.lineNumber.copyWith(color: stize.onTransit),
              );
            },
          ),
        ],
      ),
    );
  }

  /// The persistent global search row for the panel (stops / streets / lines) —
  /// visible in all views (decision #6). The hamburger sits here and ONLY on the
  /// nearby (root) view (owner R1 #4). Reuses the same search state as the
  /// legacy bottom search, so results render in the panel body.
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
        Expanded(
          child: Material(
            borderRadius: BorderRadius.circular(24),
            elevation: 3,
            color: theme.colorScheme.surface,
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(
                  StizeIcons.search,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: l10n.searchHint,
                      border: InputBorder.none,
                      // The pill around it is the ground; no second fill.
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                if (_searching)
                  IconButton(
                    icon: const Icon(StizeIcons.close),
                    onPressed: _clearSearch,
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
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
  // One diagnostics line for the followed vehicle's catch-up: live gap (metres
  // behind the plan's predicted-now spot) and display speed (m/s). Reads the
  // timed player directly; falls back to a dash when nothing is being followed.
  String _catchUpDiagLine() {
    final key = _selectedVehicleKey;
    final timed = key == null ? null : _vehAnimator.trackFor(key)?.timed;
    if (timed == null) return 'VEH catchUp gap - plan - vel - age -';
    final now = DateTime.now();
    // `plan` vs `vel` is the pair that diagnoses jitter: the plan's own speed
    // against the marker's. Tracking is healthy when they sit on top of each
    // other with gap ≈ 0. `vel` swinging around a steady `plan` means the
    // catch-up loop is oscillating; both swinging together means the plan is.
    //
    // `age` is the live board age driving the staleness gate; `HOLD` means it
    // has passed 45 s, so this marker has stopped predicting and stands still.
    final age = timed.boardAgeSeconds(now);
    return 'VEH catchUp gap ${timed.catchUpGap(now).toStringAsFixed(2)}m '
        'plan ${timed.planSpeed(now).toStringAsFixed(2)} '
        'vel ${timed.displaySpeed.toStringAsFixed(2)}m/s '
        'age ${age.toStringAsFixed(0)}s${timed.isStale(now) ? " HOLD" : ""}';
  }

  // The pause gate's decision for the followed vehicle's next few stops, so the
  // owner sees on screen WHY a pause fires (or doesn't): `+42m` ahead, projection
  // moved off its true spot by `off8m`, on/off-shape, and DWELL vs glide.
  String _dwellDiagLine() {
    final key = _selectedVehicleKey;
    final timed = key == null ? null : _vehAnimator.trackFor(key)?.timed;
    if (timed == null) return 'VEH dwell -';
    final stops = timed.upcomingStopDiag();
    if (stops.isEmpty) return 'VEH dwell (no stops ahead)';
    final parts = stops.map(
      (s) =>
          '+${s.aheadM.toStringAsFixed(0)}m off${s.offShapeM.toStringAsFixed(0)}m '
          '${s.onShape ? "on" : "OFF"}→${s.dwells ? "DWELL" : "glide"}',
    );
    return 'VEH dwell ${parts.join("  ")}';
  }

  // The followed marker's standstill, explained as an EVENT: the instant its
  // display speed drops below 0.5 m/s, name the CAUSE so nobody has to guess
  // why a bus is parked mid-block. The four causes are mutually exclusive and
  // ordered by precedence:
  //   HOLD    — the board is stale (>45 s), so the target is pinned to the last
  //             fix and the marker legitimately stops until a fresh board.
  //   spent   — the plan is exhausted (reached its end / the distance horizon).
  //   DWELL   — the plan ITSELF predicts a standstill here (plan speed ≈ 0):
  //             a real pause at the named stop.
  //   CONTOUR — the plan is still moving but the marker is not: the catch-up /
  //             gap-contour fault (a mid-block standstill with NO dwell — this
  //             is the "stopped but every upcoming stop shows glide" case).
  String _stopCauseDiagLine() {
    final key = _selectedVehicleKey;
    final timed = key == null ? null : _vehAnimator.trackFor(key)?.timed;
    if (timed == null) return 'VEH stopWhy -';
    final now = DateTime.now();
    final vel = timed.displaySpeed;
    final pos = timed.position;
    final at =
        '@${pos.latitude.toStringAsFixed(5)},'
        '${pos.longitude.toStringAsFixed(5)}';
    if (vel >= 0.5) return 'VEH stopWhy moving ${vel.toStringAsFixed(2)}m/s';
    final plan = timed.planSpeed(now);
    final gap = timed.catchUpGap(now);
    final ahead = timed.upcomingStopDiag(count: 1);
    final near = ahead.isEmpty ? null : ahead.first;
    final String cause;
    if (timed.isStale(now)) {
      cause =
          'HOLD stale board '
          '(age ${timed.boardAgeSeconds(now).toStringAsFixed(0)}s>45) — pinned to fix';
    } else if (timed.isGliding(now)) {
      cause =
          'GLIDE-END coasting to rest at plan end '
          '(vel ${vel.toStringAsFixed(2)}m/s, buffering a late board)';
    } else if (!timed.isPlaying(now)) {
      cause = 'plan spent (end/horizon reached)';
    } else if (plan < 0.5) {
      cause = near == null
          ? 'DWELL: plan standstill (no stop info)'
          : 'DWELL: plan stopped +${near.aheadM.toStringAsFixed(0)}m '
                'off${near.offShapeM.toStringAsFixed(0)}m '
                '${near.dwells ? "dwell" : "glide?!"}';
    } else {
      cause =
          'CONTOUR: plan ${plan.toStringAsFixed(2)}m/s but vel '
          '${vel.toStringAsFixed(2)}, gap ${gap.toStringAsFixed(1)}m — parked off-plan';
    }
    return 'VEH stopWhy $cause $at';
  }

  // How stale the vehicles' REAL fixes are, against how stale their boards
  // claim to be. `as_of` is the backend's last successful *fetch*, so re-fetching
  // a board the upstream hasn't refreshed re-stamps it young while the fix
  // underneath is minutes old — and the whole prediction hangs off that stamp.
  // Measured live: two views of one bus 121 m apart from GPS fixes identical to
  // the metre, purely because their as_of differed by 36 s.
  //
  // Read-only evidence for a later call on whether the backend should stop
  // re-stamping. Low numbers → the root fix is painless; high → the feed itself
  // is the conversation.
  String _fixAgeDiagLine() {
    final s = _vehAnimator.fixAgeStats();
    if (s.total == 0) return 'VEH fixAge -';
    return 'VEH fixAge >45s ${s.over45}/${s.total} '
        '>90s ${s.over90}/${s.total} (real fix age, not as_of)';
  }

  // How old each recent board was when it landed, and how many of those doomed
  // the marker to a freeze before the next one (> 15 s; see the field's note).
  String _boardAgeDiagLine() {
    if (_boardAgePolls.isEmpty) return 'VEH boardAge@poll -';
    final doomed = _boardAgePolls.where((a) => a > 15).length;
    final worst = _boardAgePolls.reduce((a, b) => a > b ? a : b);
    return 'VEH boardAge@poll ${_boardAgePolls.join(",")} '
        'max ${worst}s freeze-bound $doomed/${_boardAgePolls.length}';
  }

  Widget _stopDiagnosticsOverlay(ThemeData theme) {
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
      _catchUpDiagLine(),
      _dwellDiagLine(),
      _stopCauseDiagLine(),
      'FOCUS layersAdded $_focusLayersAdded stops ${_focus?.stops.length ?? 0} '
          'err ${_focusLayerError ?? "-"}',
      // The real test for the followed line's stop pins: of the focus stops in
      // view, how many actually draw. `focus:0/8` with layersAdded true + err -
      // = layer & source are fine but nothing paints (image not resolved for the
      // layer, or z-order); `focus:8/8` = pins ARE there (trust this over eyes).
      'FOCUS render ${renderStats('focus', (_focus?.stops ?? const <Stop>[]).map((s) => (lat: s.lat, lon: s.lon)))}',
      _boardAgeDiagLine(),
      _fixAgeDiagLine(),
    ];

    return SafeArea(
      child: Align(
        // Bottom-right (owner, 2026-11-23): out of the way of the panel, the
        // search and the top-right controls. On mobile it sits above the sheet.
        alignment: Alignment.bottomRight,
        child: IgnorePointer(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            margin: EdgeInsets.only(
              right: 12,
              bottom: _panelActive
                  ? 12
                  : _mobileSheetPx +
                        (_oneScrollRoot ? MapSearchPill.height + 32 : 8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final line in lines)
                  Text(
                    line,
                    // ds-ok: staging-only diagnostics overlay.
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.35,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A small top-centered hint shown at far-out zoom when no live vehicles are
  /// in the bounded fetch area — the "zoom in to see transport" nudge (F5).
  Widget _zoomHint(AppLocalizations l10n, ThemeData theme) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          // Clear of the top buttons.
          padding: const EdgeInsets.only(top: 72),
          child: PointerInterceptor(
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(20),
              color: theme.colorScheme.surface.withValues(alpha: 0.92),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      StizeIcons.zoomIn,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.mapZoomInForVehicles,
                      style: StizeText.of(context).caption,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _focusPanel(ThemeData theme) {
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
    final scheduled = focus?.scheduled ?? false;
    final color = vehicleColor(type);
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: PointerInterceptor(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              // Stiže: the floating map-control shadow; OFF keeps the prior soft
              // drop shadow (killswitch).
              boxShadow: StizeShadow.shadowMapControl,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      vehicleGlyph(
                        type,
                        size: 16,
                        color: StizeColors.of(context).onTransit,
                      ),
                      const SizedBox(width: 8),
                      Builder(
                        builder: (context) {
                          final stize = StizeColors.of(context);
                          return Text(
                            line,
                            style: StizeType.lineNumber.copyWith(
                              color: stize.onTransit,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        // Route terminals once the shape is loaded; until then
                        // (or on a shape that failed to load) a neutral label so
                        // the bar is still complete and exitable.
                        subtitle ??
                            AppLocalizations.of(context).followingVehicle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: StizeText.of(context).body,
                      ),
                      // A tapped schedule-predicted object honestly says so — its
                      // position is a GTFS estimate, not a live fix.
                      if (scheduled)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              StizeIcons.clock,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                AppLocalizations.of(context).vehicleScheduled,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: StizeText.of(context).note.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(StizeIcons.close),
                  onPressed: _closeVehicleContext,
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                ),
              ],
            ),
          ),
        ),
      ),
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
              _roundButton(
                theme,
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
                _jamModeButton(theme),
                // Hides itself — gap and all — while the flag is off, so the
                // killswitch leaves this stack exactly as production has it.
                const VehicleModeToggle(),
                // On mobile "where am I" lives in the search pill only; a level
                // no longer brings a second round button back (owner,
                // 2026-11-23). Desktop keeps it.
                if (_panelActive)
                  _roundButton(
                    theme,
                    icon: StizeIcons.locate,
                    onTap: _recenterOnMe,
                  ),
                if (_showZoomControls) ...[
                  const SizedBox(height: 12),
                  _zoomControl(theme),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _zoomControl(ThemeData theme) {
    return PointerInterceptor(
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 3,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(StizeIcons.plus),
              onPressed: () => _zoomBy(1),
            ),
            Divider(height: 1, thickness: 1, color: theme.dividerColor),
            IconButton(
              icon: const Icon(StizeIcons.minus),
              onPressed: () => _zoomBy(-1),
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
  Widget _jamModeButton(ThemeData theme) {
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
    final loud = relevant > 0;
    final l10n = AppLocalizations.of(context);
    final iconColor = _jamModeOn
        ? Colors.white
        : (loud
              ? StizeColors.of(context).jam
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PointerInterceptor(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: _jamModeOn
                  ? StizeColors.of(context).jam
                  : theme.colorScheme.surface,
              elevation: 3,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                // Round ink on a round button (the theme's icon-button shape
                // is a 12px square, which showed as a square inside the circle).
                style: IconButton.styleFrom(shape: const CircleBorder()),
                icon: Icon(StizeIcons.warning, color: iconColor),
                tooltip: l10n.jamModeTooltip,
                onPressed: () => _setJamMode(!_jamModeOn),
              ),
            ),
            // Red count badge ONLY for context-relevant jams — a far-away jam
            // never lights it up.
            if (loud)
              Positioned(
                right: -2,
                top: -2,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    decoration: BoxDecoration(
                      color: StizeColors.of(context).alertCount,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$relevant',
                      textAlign: TextAlign.center,
                      style: StizeType.control.copyWith(
                        color: Colors.white,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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

  Widget _roundButton(
    ThemeData theme, {
    required IconData icon,
    String? tooltip,
    VoidCallback? onTap,
  }) {
    return PointerInterceptor(
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 3,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(icon: Icon(icon), tooltip: tooltip, onPressed: onTap),
      ),
    );
  }

  // No declarative layers. The ambient stop layers AND the focused-line view are
  // both added imperatively (see [_addStopLayers] / [_syncFocusLayers]) to dodge
  // maplibre 0.3.5's positional LayerManager, which reconciles the declarative
  // list by index with unawaited add/remove and deterministically dropped whole
  // layers (a pure-bus stop lost its pin on prod). Going imperative also lets the
  // focus route be inserted *below* the vehicle symbols (belowLayerId), so it
  // never paints over the coin being followed. "My position" is a WidgetLayer
  // marker (in build) so it can't be culled at low zoom (X2).
  List<Layer> _buildLayers() => const [];

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
