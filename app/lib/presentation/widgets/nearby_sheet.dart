import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/context_slot.dart';
import '../../core/design/stize_tokens.dart';
import '../../domain/models/geocode_result.dart';
import '../../domain/models/line_info.dart';
import '../../domain/models/nearby_arrival.dart';
import '../../domain/models/stop.dart';
import 'flat_cards.dart';
import 'nearby_view.dart';
import 'sheet_chrome.dart';

// Re-exported so existing importers keep working after the data logic moved to
// [NearbyView].
export 'nearby_view.dart'
    show shouldRefetchNearby, kNearbyRefetchDistanceMeters;

/// The "Nearby" surface (the mobile default since `nearby_list` retired): a
/// draggable bottom sheet over the map. The list, fetch, and empty-state logic
/// now live in the reusable [NearbyView] (shared with the desktop context
/// panel); this is just the sheet shell around it.
class NearbySheet extends StatelessWidget {
  const NearbySheet({
    super.key,
    required this.userLocation,
    required this.locationDenied,
    required this.active,
    required this.onEnableLocation,
    this.onTapGroup,
    this.onSelectStop,
    this.onSelectLine,
    this.onSelectPlace,
    this.onHeightChanged,
    this.controller,
    this.banner,
    this.oneScroll = false,
    this.maxSize,
    this.searchController,
    this.searchActive = false,
    this.levelHeader,
    this.levelBody,
    this.headerOwnsHandle = false,
  });

  /// The level header draws its own grabber (the follow card's line colour).
  final bool headerOwnsHandle;

  /// Drives the sheet's height from the host (open a level at half, close back
  /// to peek). The sheet itself is never rebuilt between levels, so its height
  /// stays continuous: one sheet, only its content changes.
  final DraggableScrollableController? controller;

  /// Contextual guide strip under the search (see NearbyView.banner).
  final Widget? banner;

  /// One-scroll home (owner, 2026-11-23): no snapping, no grabber, the sheet
  /// rises continuously up to [maxSize] (just under the map's search pill) and
  /// then its list scrolls; cards run edge to edge. The search is the pill on
  /// the map ([searchController] / [searchActive]), not a row in the sheet.
  final bool oneScroll;
  final double? maxSize;
  final TextEditingController? searchController;
  final bool searchActive;

  /// Where the one-scroll sheet rests when the home opens: about one and a
  /// half cards (owner, 2026-11-25, after Transit), so the map keeps most of
  /// the screen and a half card says "there is more".
  static const double oneScrollRestPx = 190;

  /// [oneScrollRestPx] as a fraction of a body of height [h].
  static double oneScrollRestFor(double h) =>
      h <= 0 ? 0.25 : (oneScrollRestPx / h).clamp(0.2, 0.42);

  /// Sheet size before search focus raised it, so Cancel returns "as it was".
  static final _preSearch = Expando<double>();

  void _toDetent(double size) {
    final c = controller;
    if (c == null || !c.isAttached) return;
    _preSearch[c] ??= c.size;
    c.animateTo(size, duration: StizeMotion.slow, curve: StizeMotion.smoothOut);
  }

  void _restoreDetent() {
    final c = controller;
    if (c == null || !c.isAttached) return;
    final back = _preSearch[c] ?? kSheetPeek;
    _preSearch[c] = null;
    c.animateTo(back, duration: StizeMotion.slow, curve: StizeMotion.smoothOut);
  }

  /// When a level is open (a stop, My stops, a vehicle model), its header and
  /// scrollable body replace the Nearby view INSIDE this same sheet.
  final Widget? levelHeader;
  final Widget Function(ScrollController scrollController)? levelBody;

  /// The user's latest position fix, or null when there's no fix yet.
  final ll.LatLng? userLocation;

  /// Location permission was refused/revoked this session.
  final bool locationDenied;

  /// The map tab is visible and the app is foregrounded — pause polling when not.
  final bool active;

  /// Ask for a location fix: the map's recenter, our only permission gesture.
  final VoidCallback onEnableLocation;

  final void Function(NearbyGroup group)? onTapGroup;

  /// A search result tapped: open that stop, line or place (owner C#3).
  final void Function(Stop stop)? onSelectStop;
  final void Function(LineInfo line)? onSelectLine;
  final void Function(GeocodeResult place)? onSelectPlace;

  /// The sheet's pixel height on every frame, to keep a followed vehicle above.
  final ValueChanged<double>? onHeightChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewport = MediaQuery.sizeOf(context).height;
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        onHeightChanged?.call(n.extent * viewport);
        return false;
      },
      child: DraggableScrollableSheet(
        controller: controller,
        // Unified detents (owner R2 #4): large is NOT fullscreen — a strip of map
        // always stays on top.
        initialChildSize: oneScroll ? oneScrollRestFor(viewport) : kSheetPeek,
        // One-scroll: the list never sinks below its resting place, so a pull
        // down at rest overscrolls the list and refreshes it (owner,
        // 2026-11-23: refresh only showed up after dragging all the way down).
        minChildSize: oneScroll ? oneScrollRestFor(viewport) : 0.12,
        // Levels (a stop, the guide…) rise as high as Nearby does: just under
        // the close button's row (owner, 2026-11-25: the guide stopped short).
        maxChildSize: maxSize ?? kSheetLarge,
        snap: !oneScroll,
        // Two resting places for a drag (owner, 2026-11-23): stopping halfway
        // and then pulling again felt like friction. Half is still used when
        // a level opens programmatically, so the stop stays visible on the map.
        // A STABLE list: the sheet compares snapSizes by identity on every
        // rebuild and snaps when it differs, and the follow ticks rebuilds
        // ~15×/s, so a fresh list each build cancelled every body drag (owner,
        // 2026-11-26: the follow sheet moved only by its handle).
        snapSizes: oneScroll ? null : _snapSizesFor(maxSize ?? kSheetLarge),
        builder: (context, scrollController) {
          // PointerInterceptor stops scroll/drag/taps on the sheet from falling
          // through to the MapLibre platform view underneath on web. No-op on
          // mobile.
          return PointerInterceptor(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: kSheetRadius,
                // Stiže: the system sheet shadow; OFF keeps the prior soft one.
                boxShadow: StizeShadow.shadowSheet,
              ),
              // Everything outside the list (handle, search, guide strip,
              // level header) drags the sheet too: only the list's own
              // scrollable used to, so a drag on the search or the strip did
              // nothing.
              child: _SheetDragArea(
                snap: !oneScroll,
                large: maxSize ?? kSheetLarge,
                controller: controller,
                viewport: viewport,
                child: FlatCards(
                  // One-scroll: the first card itself carries the sheet's top
                  // radius, nothing peeks above it.
                  child: ClipRRect(
                    borderRadius: oneScroll || headerOwnsHandle
                        ? kSheetRadius
                        : BorderRadius.zero,
                    child: Column(
                      children: [
                        if (!oneScroll && !headerOwnsHandle)
                          const SheetDragHandle(),
                        if (levelBody != null) ...[
                          ?levelHeader,
                          Expanded(child: levelBody!(scrollController)),
                        ] else
                          Expanded(
                            child: _TopDetentScroll(
                              sheetScroll: scrollController,
                              controller: controller,
                              top: maxSize ?? kSheetLarge,
                              rest: oneScroll
                                  ? oneScrollRestFor(viewport)
                                  : kSheetPeek,
                              builder: (scrollController) => NearbyView(
                                userLocation: userLocation,
                                locationDenied: locationDenied,
                                active: active,
                                onEnableLocation: onEnableLocation,
                                onTapGroup: onTapGroup,
                                onSelectStop: onSelectStop,
                                onSelectLine: onSelectLine,
                                onSelectPlace: onSelectPlace,
                                scrollController: scrollController,
                                banner: banner,
                                showLocalSearch: !oneScroll,
                                externalSearch: searchController,
                                externalSearchActive: searchActive,
                                onSearchFocus: () =>
                                    _toDetent(maxSize ?? kSheetLarge),
                                onSearchCancel: _restoreDetent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One list instance per top detent (see [NearbySheet]'s snapSizes).
final Map<double, List<double>> _snapSizesCache = {};
List<double> _snapSizesFor(double top) =>
    (_snapSizesCache.length > 8 ? (_snapSizesCache..clear()) : _snapSizesCache)
        .putIfAbsent(top, () => List.unmodifiable([kSheetPeek, top]));

/// Vertical drags that land outside the sheet's scrollable move the sheet,
/// and a release snaps to peek or large (by flick direction, else nearest).
class _SheetDragArea extends StatelessWidget {
  const _SheetDragArea({
    this.snap = true,
    this.large = kSheetLarge,
    required this.controller,
    required this.viewport,
    required this.child,
  });

  final bool snap;

  /// The top detent.
  final double large;
  final DraggableScrollableController? controller;
  final double viewport;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) return child;
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _SheetDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_SheetDragRecognizer>(
              () => _SheetDragRecognizer(debugOwner: this),
              (r) {
                r.onUpdate = (d) => _update(c, d);
                r.onEnd = (d) => _end(c, d);
              },
            ),
      },
      child: child,
    );
  }

  void _update(DraggableScrollableController c, DragUpdateDetails d) {
    if (!c.isAttached) return;
    final next = (c.size - (d.primaryDelta ?? 0) / viewport).clamp(
      snap ? 0.12 : NearbySheet.oneScrollRestFor(viewport),
      snap ? large : 1.0,
    );
    c.jumpTo(next);
  }

  void _end(DraggableScrollableController c, DragEndDetails d) {
    if (!c.isAttached || !snap) return;
    final v = d.primaryVelocity ?? 0;
    final double target;
    if (v < -300) {
      target = large;
    } else if (v > 300) {
      target = c.size < kSheetPeek ? 0.12 : kSheetPeek;
    } else {
      target = (c.size - kSheetPeek).abs() < (c.size - large).abs()
          ? kSheetPeek
          : large;
    }
    c.animateTo(
      target,
      duration: StizeMotion.slow,
      curve: StizeMotion.smoothOut,
    );
  }
}

/// Pointers the Nearby list took at the top detent ([_TopDetentScroll]): the
/// sheet's drag area leaves them to the list, so a pull at the list's top
/// refreshes instead of moving the sheet.
final Set<int> _listOwnedPointers = {};

class _SheetDragRecognizer extends VerticalDragGestureRecognizer {
  _SheetDragRecognizer({super.debugOwner});

  @override
  bool isPointerAllowed(PointerEvent event) =>
      !_listOwnedPointers.contains(event.pointer) &&
      super.isPointerAllowed(event);
}

/// At the top detent the Nearby list scrolls on a controller of its own, so a
/// pull down at its top stretches the first card and refreshes (owner,
/// 2026-11-26, option 1) instead of shrinking the sheet, which is what the
/// sheet's own scroll position does with every downward drag at its top.
///
/// The sheet's controller then rests on an empty scrollable, so the handle,
/// the header and [DraggableScrollableController] calls keep moving the sheet,
/// and a quick flick down from the list's top collapses it to [rest].
///
/// Swaps wait for the fingers to lift and the list to stop, so a drag or a
/// fling is never cut halfway.
class _TopDetentScroll extends StatefulWidget {
  const _TopDetentScroll({
    required this.sheetScroll,
    required this.controller,
    required this.top,
    required this.rest,
    required this.builder,
  });

  final ScrollController sheetScroll;
  final DraggableScrollableController? controller;

  /// The top detent, as a fraction of the screen.
  final double top;

  /// Where a flick down collapses the sheet to.
  final double rest;

  final Widget Function(ScrollController scrollController) builder;

  @override
  State<_TopDetentScroll> createState() => _TopDetentScrollState();
}

class _TopDetentScrollState extends State<_TopDetentScroll> {
  /// The list's own controller while the sheet sits at its top detent.
  ScrollController? _own;
  bool _want = false;
  bool _collapsing = false;
  int _pointers = 0;
  final VelocityTracker _velocity = VelocityTracker.withKind(
    PointerDeviceKind.touch,
  );
  double _downY = 0;
  bool _downAtTop = false;

  bool get _detached => _own != null;

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  bool _onExtent(DraggableScrollableNotification n) {
    // Hysteresis: hold the list at the top a hair below the detent so the end
    // of a snap animation does not flip it back.
    final want = _detached
        ? n.extent >= widget.top - 0.02
        : n.extent >= widget.top - 0.01;
    if (want != _want) {
      _want = want;
      _settle();
    }
    return false;
  }

  bool _onScroll(ScrollNotification n) {
    // The end is announced before the position stops reporting "scrolling",
    // so look again once this notification has run.
    if (n is ScrollEndNotification) Future.microtask(_settle);
    return false;
  }

  bool _scrolling() {
    final c = _detached ? _own! : widget.sheetScroll;
    return c.hasClients && c.positions.any((p) => p.isScrollingNotifier.value);
  }

  /// Apply [_want] once nothing is in motion under a finger.
  void _settle() {
    if (!mounted || _collapsing || _pointers > 0 || _want == _detached) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _settle());
      return;
    }
    if (_want) {
      if (_scrolling()) return;
      final s = widget.sheetScroll;
      final offset = s.hasClients && s.positions.length == 1 ? s.offset : 0.0;
      setState(() => _own = ScrollController(initialScrollOffset: offset));
      // A snap cut a hair short of the detent finishes on the empty scrollable.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = widget.controller;
        if (mounted && c != null && c.isAttached && c.size < widget.top) {
          c.jumpTo(widget.top);
        }
      });
    } else {
      final old = _own;
      setState(() => _own = null);
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    }
  }

  void _down(PointerDownEvent e) {
    _pointers++;
    if (_detached) _listOwnedPointers.add(e.pointer);
    _velocity.addPosition(e.timeStamp, e.position);
    _downY = e.position.dy;
    final own = _own;
    _downAtTop = own != null && own.hasClients && own.offset <= 0;
  }

  void _up(PointerEvent e) {
    _pointers = (_pointers - 1).clamp(0, 99);
    _listOwnedPointers.remove(e.pointer);
    if (e is PointerUpEvent && _detached && _downAtTop) {
      final v = _velocity.getVelocity().pixelsPerSecond.dy;
      if (v > 800 && e.position.dy - _downY > 12) {
        _collapse();
        return;
      }
    }
    _settle();
  }

  Future<void> _collapse() async {
    final c = widget.controller;
    if (c == null || !c.isAttached) return;
    _collapsing = true;
    try {
      await c.animateTo(
        widget.rest,
        duration: StizeMotion.medium,
        curve: StizeMotion.smoothOut,
      );
    } finally {
      _collapsing = false;
      _want = c.isAttached && c.size >= widget.top - 0.01;
      _settle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final own = _own;
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: _onExtent,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: Listener(
          onPointerDown: _down,
          onPointerMove: (e) => _velocity.addPosition(e.timeStamp, e.position),
          onPointerUp: _up,
          onPointerCancel: _up,
          child: Stack(
            // Positioned children only: the Stack takes the list's full size.
            children: [
              if (own != null)
                // Keeps the sheet's controller attached while the list
                // scrolls on its own, so the sheet can still be moved.
                Positioned(
                  key: const ValueKey('sheet-scroll'),
                  left: 0,
                  top: 0,
                  width: 0,
                  height: 0,
                  child: SingleChildScrollView(
                    controller: widget.sheetScroll,
                    physics: const NeverScrollableScrollPhysics(),
                    child: const SizedBox.shrink(),
                  ),
                ),
              // Keyed: without it the list matched the slot the empty
              // scrollable takes, lost its state on every swap and refetched
              // ("Finding lines" flashed while the sheet moved, owner
              // 2026-11-26).
              Positioned.fill(
                key: const ValueKey('list'),
                child: widget.builder(own ?? widget.sheetScroll),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
