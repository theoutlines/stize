part of '../home_map_screen.dart';

// App lifecycle (thermal: zero work while hidden): pause and resume every
// timer and ticker, and the 30 s refresh tick.

extension _MapLifecycle on _HomeMapScreenState {
  void _pauseActivity() {
    if (_paused) return;
    _paused = true;
    _hiddenAt = DateTime.now();
    _vehAnim.stop();
    _stopVehDriver();
    _vehiclesTimer?.cancel();
    _vehiclesTimer = null;
  }

  void _resumeActivity() {
    if (!_paused) return;
    _paused = false;
    // Hold follow across the resume: the tab-return canvas re-layout can surface
    // a spurious "gesture" camera event that would otherwise break it. The next
    // follow tick re-centres on the marker, so a re-anchor jump just re-centres.
    if (_follow.active) {
      _follow.resumeGuardUntil = DateTime.now().add(const Duration(seconds: 1));
    }
    final hiddenAt = _hiddenAt;
    if (hiddenAt != null) {
      // Discount the time spent hidden so a vehicle isn't declared stuck just
      // because the app was in the background across its dwell.
      _vehAnimator.shiftClock(DateTime.now().difference(hiddenAt));
      _hiddenAt = null;
    }
    _startVehiclesTimer();
    // Refresh right away on resume (both modes): the aquarium off-demand, or the
    // active stop/vehicle context on-demand — so a vehicle isn't left on a stale
    // fix after the tab comes back. The fresh board then re-anchors the timed
    // players and the marker catches up to its real position.
    _refreshTick();
    // Restart the driver so the timed players advance the moment we're back —
    // otherwise the marker sits frozen until the refetch lands (and a stale/503
    // board would leave it frozen with no ticker running at all).
    if (_vehAnimator.tracks.isNotEmpty) {
      _startVehDriver();
      _paintVehicles();
    }
  }

  void _startVehiclesTimer() {
    _vehiclesTimer?.cancel();
    _vehiclesTimer = Timer.periodic(
      _vehiclesRefreshInterval,
      (_) => _refreshTick(),
    );
  }

  /// The steady 30s refresh, matched to the backend cache. In on-demand mode the
  /// background aquarium is off, so instead the ACTIVE context (a stop, or a
  /// followed vehicle still tied to its stop) is kept live by re-fetching that
  /// stop's arrivals — otherwise the markers play their trajectory to the end of
  /// `as_of` and freeze forever, since the sheet's own poll dies when it closes.
  /// This runs regardless of follow, so following never freezes the data. When
  /// off-demand it drives the viewport aquarium exactly as before.
  void _refreshTick() {
    final action = mapRefreshAction(
      onDemand: _onDemand,
      stopContextId: _stopContextId,
    );
    _diag.refreshTicks++;
    // Refresh the jam board on the same 30s cadence (no-op / no request when the
    // flag is off — the provider short-circuits to an empty board).
    if (ref.read(jamDetectionEnabledProvider)) ref.invalidate(jamsProvider);
    switch (action) {
      case MapRefresh.aquarium:
        _loadVehiclesForVisibleArea(force: true);
      case MapRefresh.pollStop:
        ref.invalidate(arrivalsProvider(_stopContextId!));
      case MapRefresh.none:
        break;
    }
  }
}
