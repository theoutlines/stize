part of '../home_map_screen.dart';

// One-scroll home (mobile): the search pill riding on the sheet, the sheet's
// close above it, and the top-right buttons it pushes up.

extension _MapPill on _HomeMapScreenState {
  /// What the close above the mobile sheet does now, or null when the level
  /// has none (Nearby root, a nested level with its back link, a model leaf).
  VoidCallback? get _mobileSheetCloseAction {
    if (_panelActive || _lineOnlyFocus) return null;
    if (_selectedVehicleKey != null) return _closeVehicleContext;
    if (_slotModel != null) return null;
    if (_levels.length == 1) return _closeAllLevels;
    return null;
  }

  /// The close of the mobile sheet, riding just above its right edge; stops
  /// under the status bar when the sheet is at its tallest.
  Widget _mapSheetClose(Size size) {
    final action = _mobileSheetCloseAction;
    return AnimatedBuilder(
      animation: _sheetCtl,
      builder: (context, child) {
        final top = _sheetCloseTopFor(size);
        return Positioned(
          right: StizeSpace.space4,
          top: action == null || top == null ? -400 : top,
          child: IgnorePointer(ignoring: action == null, child: child!),
        );
      },
      child: MapSheetCloseButton(onPressed: () => action?.call()),
    );
  }

  /// The close button's top for the current sheet height, or null before the
  /// sheet is attached.
  double? _sheetCloseTopFor(Size size) {
    if (!_sheetCtl.isAttached) return null;
    final sheetTop = _bodyH(size) * (1 - _sheetCtl.size);
    final riding =
        sheetTop - MapSheetCloseButton.gap - MapSheetCloseButton.size;
    final floor = MediaQuery.paddingOf(context).top + StizeSpace.space3;
    return riding < floor ? floor : riding;
  }

  /// Typing in the pill raises the list to just under the pinned pill; an
  /// emptied query lets it settle back to rest.
  void _onPillQuery() {
    if (!_pillActive || !_sheetCtl.isAttached) return;
    final size = MediaQuery.sizeOf(context);
    final want = _pillCtl.text.isEmpty
        ? NearbySheet.oneScrollRestFor(size.height)
        : _oneScrollMax(size);
    if ((_sheetCtl.size - want).abs() < 0.01) return;
    _sheetCtl.animateTo(
      want,
      duration: StizeMotion.slow,
      curve: StizeMotion.smoothOut,
    );
  }

  /// The sheet rises to just under the pinned pill, then its list scrolls.
  double _oneScrollMax(Size size) {
    final top = _pillPinnedTop() + MapSearchPill.height + StizeSpace.space4;
    final h = _bodyH(size);
    return ((h - top) / h).clamp(0.5, 0.95);
  }

  /// The pill's top for the current sheet height: it rides on the map just
  /// above the sheet, and stops under the status bar.
  double _pillTopFor(Size size) {
    // Searching with a query: the pill stays pinned at the top.
    if (_pillActive && _pillCtl.text.isNotEmpty) return _pillPinnedTop();
    final s = _sheetCtl.isAttached
        ? _sheetCtl.size
        : NearbySheet.oneScrollRestFor(size.height);
    final sheetTop = _bodyH(size) * (1 - s);
    final riding = sheetTop - MapSearchPill.height - StizeSpace.space4;
    return riding < _pillPinnedTop() ? _pillPinnedTop() : riding;
  }

  Widget _searchPill(AppLocalizations l10n, Size size) {
    return AnimatedBuilder(
      animation: _sheetCtl,
      builder: (context, child) => Positioned(
        left: StizeSpace.space4,
        right: StizeSpace.space4,
        top: _oneScrollRoot ? _pillTopFor(size) : -400,
        child: IgnorePointer(ignoring: !_oneScrollRoot, child: child!),
      ),
      child: MapSearchPill(
        controller: _pillCtl,
        focusNode: _pillFocus,
        active: _pillActive,
        placeLabel: _browsePlaceLabel(l10n),
        away: _browse.point != null,
        onLocate: _recenterOnMe,
        // Nothing moves on the tap itself: iOS drops the keyboard when the
        // focused field jumps during the tap (owner, 2026-11-23). The list
        // rises once a query is typed (see _onPillQuery).
        onActivate: () => _setState(() => _pillActive = true),
        onClose: () {
          _pillCtl.clear();
          _pillFocus.unfocus();
          _setState(() => _pillActive = false);
          if (_sheetCtl.isAttached) {
            _sheetCtl.animateTo(
              NearbySheet.oneScrollRestFor(size.height),
              duration: StizeMotion.medium,
              curve: StizeMotion.smoothOut,
            );
          }
        },
      ),
    );
  }

  /// The round map buttons, pushed up past the top edge as the rising pill
  /// reaches them (owner, 2026-11-23). Desktop and level views: unmoved.
  Widget _pushedTopButtons(ThemeData theme, Size size) {
    final buttons = _topButtons(theme);
    // The builder stays in the tree in every state, so the buttons (and their
    // pointer interceptors) are never re-mounted when a level opens.
    return AnimatedBuilder(
      animation: _sheetCtl,
      child: buttons,
      builder: (context, child) {
        // The measured bottom of the button stack (zoom control included on
        // web); the pill pushes once it is within 12px of that edge.
        // Measured after layout, never during build (a render object can be
        // inactive mid-build).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _topButtonsKey.currentContext;
          if (ctx == null || !ctx.mounted) return;
          final box = ctx.findRenderObject();
          if (box is RenderBox && box.attached && box.hasSize) {
            _topButtonsH = box.size.height;
          }
        });
        // The right-hand button column (keyed in _topButtons) sits below the
        // status-bar inset and a 12px margin.
        final buttonsBottom =
            MediaQuery.paddingOf(context).top + 12 + _topButtonsH;
        // The rising search pill (Nearby root) or the sheet's close (a level)
        // pushes the buttons up once it reaches them.
        final closeTop = _mobileSheetCloseAction == null
            ? null
            : _sheetCloseTopFor(size);
        final gap = _oneScrollRoot
            ? _pillTopFor(size) - StizeSpace.space3 - buttonsBottom
            : (closeTop == null
                  ? 0.0
                  : closeTop - StizeSpace.space3 - buttonsBottom);
        return Transform.translate(
          offset: Offset(0, gap < 0 ? gap : 0),
          child: child,
        );
      },
    );
  }
}
