part of '../home_map_screen.dart';

// Levels of the sheet / panel: open a stop, My stops, Settings, Feedback or
// the guide over Nearby, go back, close them all, and the sheet's height.

extension _MapLevels on _HomeMapScreenState {
  /// The menu's "My stops": open the saved stops as a level (desktop panel /
  /// mobile sheet), on top of whatever is open, so back returns there.
  void _openMyStopsLevel() {
    _expandPanelIfCollapsed();
    if (_levels.isEmpty || _levels.last is! _MyStopsLevel) {
      _levels.add(const _MyStopsLevel());
    }
    _setState(() => _slotModel = null);
    _raiseSheetToHalf();
  }

  /// Pushes a non-stop level (Settings, Feedback) onto the one sheet/panel.
  void _pushLevel(_SlotLevel level) {
    _expandPanelIfCollapsed();
    final top = _levels.isEmpty ? null : _levels.last;
    if (top.runtimeType != level.runtimeType ||
        (level is _FeedbackLevel &&
            (top as _FeedbackLevel).form != level.form)) {
      _levels.add(level);
    }
    _setState(() => _slotModel = null);
    _raiseSheetToHalf();
  }

  /// Opens a page of the Belgrade guide as the next level.
  void _openGuideLevel(GuidePage page) {
    _expandPanelIfCollapsed();
    final top = _levels.isEmpty ? null : _levels.last;
    if (top is! _GuideLevel || top.page != page) {
      _levels.add(_GuideLevel(page));
    }
    _setState(() {
      _slotModel = null;
      _guideSeen = true;
    });
    _raiseSheetToHalf();
    markGuideOpened();
  }

  /// On mobile, a newly opened level shows at least at the half detent (from
  /// peek the board would barely be visible); a taller sheet keeps its height.
  void _raiseSheetToHalf() {
    if (_panelActive) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sheetCtl.isAttached) return;
      if (_sheetCtl.size < kSheetHalf - 0.01) {
        _sheetCtl.animateTo(
          kSheetHalf,
          duration: StizeMotion.slow,
          curve: StizeMotion.smoothOut,
        );
      }
    });
  }

  /// Back one level: the level below shows again (its stop context and camera
  /// restored), or Nearby when the chain is empty.
  void _popLevel() {
    if (_levels.isEmpty) return;
    final popped = _levels.removeLast();
    if (popped is _StopLevel && _onDemand && _stopContextId == popped.id) {
      _exitStopContext();
    }
    final top = _levels.isEmpty ? null : _levels.last;
    if (top is _StopLevel) {
      if (_onDemand) _enterStopContext(top.id);
      _bringStopIntoView(top.id, null);
      ref.read(openStopNameProvider.notifier).state = top.name;
    } else {
      ref.read(openStopNameProvider.notifier).state = null;
      if (top == null) _restorePreStopCamera();
    }
    _setState(() => _slotModel = null);
  }

  /// Close every level (the × on the first level, or a swipe below peek):
  /// back to Nearby, camera where the user was before the first stop.
  void _closeAllLevels() {
    final top = _levels.isEmpty ? null : _levels.last;
    if (top is _StopLevel && _onDemand && _stopContextId == top.id) {
      _exitStopContext();
    }
    _levels.clear();
    ref.read(openStopNameProvider.notifier).state = null;
    _restorePreStopCamera();
    _setState(() => _slotModel = null);
  }

  /// Mobile sheet height feed: the geometry owner gets it as before; dragging
  /// an open level below the peek detent closes all levels (swipe-to-close) and
  /// the sheet settles back at peek showing Nearby.
  void _onMobileSheetHeight(double px) {
    _setMobileSheetPx(px);
    final h = MediaQuery.sizeOf(context).height;
    if (h <= 0) return;
    final following = _selectedVehicleKey != null;
    final hasLevel = _levels.isNotEmpty || _slotModel != null || following;
    if (hasLevel && px / h < kSheetPeek - 0.1) {
      if (following) {
        _closeVehicleContext();
        return;
      }
      _closeAllLevels();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_sheetCtl.isAttached) return;
        _sheetCtl.animateTo(
          kSheetPeek,
          duration: StizeMotion.slow,
          curve: StizeMotion.smoothOut,
        );
      });
    }
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
}
