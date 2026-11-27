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
      // One search for both breakpoints: the results are the same view the
      // mobile pill drives (nearby matches, lines, stops, places).
      child: _search.session.active
          ? _nearbyView(l10n, searching: true)
          : _slotContent(l10n),
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
  String _levelTitle(SheetLevel level, AppLocalizations l10n) =>
      switch (level) {
        StopLevel(:final id, :final name) =>
          ref.watch(stopLocationProvider(id)).valueOrNull?.name ?? name ?? '',
        MyStopsLevel() => l10n.navMyStops,
        SettingsLevel() => l10n.settingsTitle,
        FeedbackLevel() => l10n.drawerFeedbackSheetTitle,
        GuideLevel(:final page) => switch (page) {
          GuidePage.home => l10n.guideTitle,
          GuidePage.readStop => l10n.guideReadStop,
          GuidePage.places => l10n.guidePlaces,
        },
      };

  /// The header of the current level; null on Nearby (root). One control per
  /// level: a "← `previous`" back link when there is a previous level, else a ×
  /// that closes back to Nearby. Same on the mobile sheet and the desktop panel.
  /// The vehicle view keeps its line row.
  Widget? _slotNavRow(AppLocalizations l10n) {
    switch (_activeView) {
      case ContextView.nearby:
        return null;
      case ContextView.stop:
      case ContextView.myStops:
      case ContextView.guide:
      case ContextView.settings:
      case ContextView.feedback:
        final top = _levels.top!;
        final title = _levelTitle(top, l10n);
        return LevelHeader(
          title: title,
          backLabel: switch (_levels.below) {
            null => null,
            final below => _levelTitle(below, l10n),
          },
          onBack: _slotBack,
          // Mobile: the close rides above the sheet (MapSheetCloseButton).
          onClose: _panelActive ? _closeAllLevels : null,
          trailing: top is StopLevel
              ? StopHeaderActions(stopId: top.id, stopName: title)
              : null,
        );
      case ContextView.vehicle:
        return _followHeader(l10n);
    }
  }

  /// The desktop panel's Nearby list. While [searching], the persistent search
  /// above the panel drives it, exactly like the mobile pill drives the sheet.
  Widget _nearbyView(AppLocalizations l10n, {bool searching = false}) {
    return NearbyView(
      userLocation: _browse.point ?? _meTo,
      locationDenied: _locationDenied,
      active: _tabActive && _appResumed,
      onEnableLocation: _recenterOnMe,
      onTapGroup: _focusNearbyVehicle,
      onSelectStop: (stop) => _openStop(stop, source: Ev.srcSearch),
      onSelectLine: _openLine,
      onSelectPlace: _openPlace,
      // The persistent global search above the panel replaces the local
      // "filter lines nearby" field (decision #6).
      showLocalSearch: false,
      hugContent: true,
      banner: searching ? null : _guideBanner(l10n),
      externalSearch: searching ? _searchController : null,
      externalSearchActive: searching,
    );
  }

  /// The active level's content (no header — the level header owns the title).
  /// [scrollController] is the mobile sheet's, so dragging the content drags
  /// the sheet; null on the desktop panel.
  Widget _slotContent(
    AppLocalizations l10n, {
    ScrollController? scrollController,
  }) {
    switch (_activeView) {
      case ContextView.nearby:
        return _nearbyView(l10n);
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
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.only(top: 8),
          child: FeedbackForm(showTitle: false, onSent: _popLevel),
        );
      case ContextView.guide:
        final page = (_levels.top! as GuideLevel).page;
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
          routeUnavailable: _follow.noRouteData,
          // Warn only if a jam is on this vehicle's direction AND ahead of it.
          jamAhead: _jamAheadForFollowed(track),
          scrollController: scrollController,
        );
    }
  }

  Widget _panelSearchField(AppLocalizations l10n, ThemeData theme) {
    // The burger lives in the search row on the nearby root — and, while
    // collapsed, in EVERY view: the context nav row (its usual back/drawer
    // chrome) is slid away, so the persistent search is the only place left to
    // reach the drawer (owner A#2: burger reachable in both states).
    final showBurger =
        _panelCollapsed || _activeView == ContextView.nearby;
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
            active: _deskSearchActive || _search.session.active,
            placeLabel: _browsePlaceLabel(l10n),
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
}
