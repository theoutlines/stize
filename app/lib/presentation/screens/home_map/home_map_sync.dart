part of '../home_map_screen.dart';

// What the map does on every build before drawing: answer requests from the
// menu (My stops, Settings, Feedback, the guide), follow the theme, the flags
// and the providers it listens to, and keep the sheet, the browse dot and the
// map padding in step with the layout. Called first thing in build().

extension _MapSync on _HomeMapScreenState {
  void _syncMapState(BuildContext context) {
    // "My stops" from the menu opens as a level in the same sheet / panel.
    ref.listen(myStopsRequestProvider, (prev, next) {
      if (prev == next) return;
      _openMyStopsLevel();
    });
    ref.listen(settingsRequestProvider, (prev, next) {
      if (prev == next) return;
      _pushLevel(const SettingsLevel());
    });
    ref.listen(coverageRequestProvider, (prev, next) {
      if (prev == next) return;
      _openCoverageLevel();
    });
    ref.listen(coverageTypesProvider, (prev, next) {
      if (_cov.mode) _refreshCoverageModeLayers();
    });
    // Coverage mode follows the level on top: on while Coverage is shown,
    // off as soon as anything else is (back, close, a stop from search).
    final covMode = _levels.top is CoverageLevel;
    if (covMode != _cov.mode) {
      _cov.mode = covMode;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyCoverageMode(covMode);
      });
    }
    ref.listen(feedbackRequestProvider, (prev, next) {
      if (prev == next) return;
      // One way to reach us: the form. With the form switched off remotely,
      // the public issue tracker is the fallback.
      if (ref.read(feedbackFormEnabledProvider)) {
        _pushLevel(const FeedbackLevel());
      } else {
        openExternalUrl(kRepoIssuesUrl);
      }
    });
    ref.listen(guideRequestProvider, (prev, next) {
      if (prev == next) return;
      _openGuideLevel(GuidePage.home);
    });
    final theme = Theme.of(context);
    _scheme = theme.colorScheme;
    final brightness = theme.brightness;

    // Follow the app theme, and Coverage's grey data-viz basemap: swap the
    // style when either changes.
    final dataviz = _levels.top is CoverageLevel;
    if (_styleBrightness == null) {
      _styleBrightness = brightness;
      _cov.styleDataviz = dataviz;
    } else if ((_styleBrightness != brightness || _cov.styleDataviz != dataviz) &&
        _controller != null) {
      _styleBrightness = brightness;
      _cov.styleDataviz = dataviz;
      _imagesReady = false;
      _controller!.setStyle(
        MapStyle.forBrightness(brightness, dataviz: dataviz),
      );
    }

    // Favourites are drawn by an imperative source now; refresh it whenever the
    // set changes (no widget rebuild needed for the markers themselves).
    ref.listen(favoriteStopLocationsProvider, (_, _) => _pushStopSources());
    ref.listen<bool>(locationAutopromptEnabledProvider, (prev, next) {
      if (next && prev != true) _autopromptLocation();
    });

    // Tram-jam overlay: whenever the jam board changes, (re)build the red segment
    // layer and the badged-vehicle set. Flag-gated (empty board when off → clears).
    ref.listen(jamsProvider, (_, next) {
      final board = next.valueOrNull;
      if (board != null) _onJamsUpdated(board);
    });

    // Coverage overlay flag: usually flips false→true once the remote config
    // resolves. When it turns on, reconcile after this frame so the layer is
    // added if the map is already zoomed out.
    final coverageEnabled = ref.watch(coverageOnMainMapEnabledProvider);
    if (coverageEnabled != _cov.enabled) {
      _cov.enabled = coverageEnabled;
      if (coverageEnabled) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _reconcileCoverageLayer(),
        );
      }
    }

    // The map mode: the Settings choice resolved against the on-demand flag.
    // Flips false→true once remote config resolves, and again whenever the user
    // switches the setting. Reconcile after the frame (clear the background
    // aquarium, or repopulate) so the switch applies without a restart.
    final onDemand =
        ref.watch(vehicleMapModeProvider) == VehicleMapMode.onDemand;
    if (onDemand != _onDemand) {
      _onDemand = onDemand;
      WidgetsBinding.instance.addPostFrameCallback((_) => _onOnDemandChanged());
    }

    // Adaptive context slot flag (killswitch): OFF = today's independent sheets,
    // untouched. The map itself is ALWAYS the same Positioned.fill widget below
    // — only the OVERLAY (panel vs sheets) changes — so crossing the breakpoint
    // never rebuilds/recreates the map (the IndexedStack/render-cycle gotcha).
    final size = MediaQuery.sizeOf(context);
    _wideNow = isWideLayout(size.width);
    // Back on the one-scroll root from a level: settle the list at rest
    // (a level leaves the sheet at its own height).
    final rootNow = _oneScrollRoot;
    if (rootNow && !_wasOneScrollRoot) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_sheetCtl.isAttached || !_oneScrollRoot) return;
        _sheetCtl.animateTo(
          NearbySheet.oneScrollRestFor(MediaQuery.sizeOf(context).height),
          duration: StizeMotion.medium,
          curve: StizeMotion.smoothOut,
        );
      });
    }
    _wasOneScrollRoot = rootNow;
    // Panel is a DESKTOP-ONLY surface: on mobile the app falls through to the
    // legacy bottom cluster, unchanged. The map is ALWAYS the same Positioned.
    // fill widget — crossing the breakpoint only swaps the overlay, never
    // rebuilds the map. Whenever the overlap GEOMETRY changes (panel width on a
    // window resize, breakpoint flip, or the mobile sheet detent), re-settle the
    // camera so the focus stays centred in the new visible area / the scene
    // shifts by the delta — one owner, [_mapInsets] (owner R3 #1/#2).
    // The nearby sheet AND the stop sheet feed their live height to the geometry
    // owner (owner R2 #3). When NEITHER is shown (desktop panel, a follow bar)
    // drop the stale value so the owner doesn't keep a phantom bottom inset.
    // (Assigned during build, no setState — the value is read just below.)
    // The follow lives in the same sheet now (owner, 2026-11-25); only a
    // line opened without a vehicle keeps its compact bar.
    final showingNearbySheet = !_panelActive && !_lineOnlyFocus;
    final mobileSheetShowing = showingNearbySheet;
    if (!mobileSheetShowing && _mobileSheetPx != 0) _mobileSheetPx = 0;

    // The map-layer dot follows the browse state (a level opening hides it,
    // the locate button clears it).
    final dotShown = _browseShowing;
    if (dotShown != _browse.dotShown) {
      _browse.dotShown = dotShown;
      WidgetsBinding.instance.addPostFrameCallback((_) => _pushBrowseDot());
    }

    final insets = _mapInsets;
    if (insets != _appliedInsets) {
      final first = _appliedInsets == null;
      // Ease only for desktop panel-geometry / breakpoint changes. A mobile
      // sheet DRAG also moves the inset, but the 66ms follow tick re-centres a
      // followed vehicle smoothly from it — a 280ms ease every drag frame would
      // lag, so we don't fire one here for the mobile-only case.
      final easeWorthy = !first && (_panelActive || _wasPanelActive);
      _wasPanelActive = _panelActive;
      _appliedInsets = insets;
      if (easeWorthy) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _onMapGeometryChanged(),
        );
      }
    }
  }
}
