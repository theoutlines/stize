import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/context_slot.dart';
import '../../domain/models/line_info.dart';
import '../../domain/models/nearby_arrival.dart';
import '../../domain/models/stop.dart';
import 'nearby_view.dart';
import 'sheet_chrome.dart';

// Re-exported so existing importers keep working after the data logic moved to
// [NearbyView].
export 'nearby_view.dart' show shouldRefetchNearby, kNearbyRefetchDistanceMeters;

/// The experimental "Nearby" surface (legacy `nearby_list` flag path): a
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
  });

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
      // Unified detents (owner R2 #4): large is NOT fullscreen — a strip of map
      // always stays on top.
      initialChildSize: kSheetPeek,
      minChildSize: 0.12,
      maxChildSize: kSheetLarge,
      snap: true,
      snapSizes: const [kSheetPeek, kSheetHalf, kSheetLarge],
      builder: (context, scrollController) {
        // PointerInterceptor stops scroll/drag/taps on the sheet from falling
        // through to the MapLibre platform view underneath on web. No-op on
        // mobile.
        return PointerInterceptor(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: kSheetRadius,
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26, blurRadius: 12, offset: Offset(0, -2)),
              ],
            ),
            child: Column(
              children: [
                const SheetDragHandle(),
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
                  ),
                ),
              ],
            ),
          ),
        );
      },
      ),
    );
  }
}
