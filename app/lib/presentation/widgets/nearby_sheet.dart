import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/context_slot.dart';
import '../../core/design/stize_tokens.dart';
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

  /// The level header draws the grabber itself (the follow card, on its line
  /// colour), so the sheet skips its own.
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

  /// Ask for a location fix (prompts on first use) — wired to the map's recenter
  /// action, the only place we request permission from a gesture.
  final VoidCallback onEnableLocation;

  final void Function(NearbyGroup group)? onTapGroup;

  /// Selecting a GLOBAL search result (stop / line) in the unified search —
  /// opens that context, like the desktop search (owner C#3).
  final void Function(Stop stop)? onSelectStop;
  final void Function(LineInfo line)? onSelectLine;

  /// Reports the sheet's current pixel height on every layout/drag frame, so the
  /// map's geometry owner can keep a followed vehicle above the sheet. Optional.
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
        maxChildSize: oneScroll ? (maxSize ?? kSheetLarge) : kSheetLarge,
        snap: !oneScroll,
        // Two resting places for a drag (owner, 2026-11-23): stopping halfway
        // and then pulling again felt like friction. Half is still used when
        // a level opens programmatically, so the stop stays visible on the map.
        snapSizes: oneScroll ? null : const [kSheetPeek, kSheetLarge],
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
                        if (!oneScroll && !headerOwnsHandle) const SheetDragHandle(),
                        if (levelBody != null) ...[
                          ?levelHeader,
                          Expanded(child: levelBody!(scrollController)),
                        ] else
                          Expanded(
                            child: NearbyView(
                              userLocation: userLocation,
                              locationDenied: locationDenied,
                              active: active,
                              onEnableLocation: onEnableLocation,
                              onTapGroup: onTapGroup,
                              onSelectStop: onSelectStop,
                              onSelectLine: onSelectLine,
                              scrollController: scrollController,
                              banner: banner,
                              showLocalSearch: !oneScroll,
                              externalSearch: searchController,
                              externalSearchActive: searchActive,
                              onSearchFocus: () => _toDetent(kSheetLarge),
                              onSearchCancel: _restoreDetent,
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

/// Vertical drags that land outside the sheet's scrollable move the sheet,
/// and a release snaps to peek or large (by flick direction, else nearest).
class _SheetDragArea extends StatelessWidget {
  const _SheetDragArea({
    this.snap = true,
    required this.controller,
    required this.viewport,
    required this.child,
  });

  final bool snap;
  final DraggableScrollableController? controller;
  final double viewport;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (d) {
        if (!c.isAttached) return;
        final next = (c.size - (d.primaryDelta ?? 0) / viewport).clamp(
          snap ? 0.12 : NearbySheet.oneScrollRestFor(viewport),
          snap ? kSheetLarge : 1.0,
        );
        c.jumpTo(next);
      },
      onVerticalDragEnd: (d) {
        if (!c.isAttached || !snap) return;
        final v = d.primaryVelocity ?? 0;
        final double target;
        if (v < -300) {
          target = kSheetLarge;
        } else if (v > 300) {
          target = c.size < kSheetPeek ? 0.12 : kSheetPeek;
        } else {
          target = (c.size - kSheetPeek).abs() < (c.size - kSheetLarge).abs()
              ? kSheetPeek
              : kSheetLarge;
        }
        c.animateTo(
          target,
          duration: StizeMotion.slow,
          curve: StizeMotion.smoothOut,
        );
      },
      child: child,
    );
  }
}
