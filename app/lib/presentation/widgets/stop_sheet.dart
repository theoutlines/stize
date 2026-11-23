import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/context_slot.dart';
import '../../core/fleet_matcher.dart';
import '../../domain/models/arrival.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import 'fleet_model_card.dart';
import 'sheet_chrome.dart';
import 'stop_board.dart';

/// Opens a stop's live arrivals as a bottom sheet *over the current map*, with
/// no screen navigation. This is the seamless replacement for pushing a whole
/// new StopScreen (which spun up a second map and re-drew the attribution): the
/// map stays put behind the sheet and the user can dismiss straight back to it.
///
/// StopScreen still exists for `/stop/:id` deep links; the in-app tap path uses
/// this sheet. The board itself is the shared [StopBoard] (the desktop context
/// panel hosts the very same widget), so the arrivals rendering lives in one
/// place.
Future<void> showStopSheet(
  BuildContext context, {
  required String stopId,
  String? stopName,
  void Function(Arrival arrival, DateTime asOf)? onFocusVehicle,
  double? initialSize,
  ValueChanged<double>? onHeightChanged,
}) {
  return showAppSheet<void>(
    context,
    // A faint scrim so the map behind stays legible — this reads as an overlay
    // on the same map, not a new screen.
    barrierColor: Colors.black.withValues(alpha: 0.08),
    builder: (_) => _StopSheet(
      stopId: stopId,
      initialStopName: stopName,
      onFocusVehicle: onFocusVehicle,
      initialSize: initialSize,
      onHeightChanged: onHeightChanged,
    ),
  );
}

/// The legacy (flag-OFF) mobile bottom-sheet shell around [StopBoard]: a
/// draggable sheet with a handle. Tapping a live row closes the sheet first,
/// then hands the arrival to the map.
///
/// "About the vehicle" opens as an **in-sheet subview** (owner B): tapping a
/// Fleet-ID badge swaps the sheet's content to the shared [FleetModelView] with
/// a back arrow that returns to the arrivals board — no second modal, no
/// close-and-reopen flash, and the sheet's detent/height stay continuous through
/// the swap (same [DraggableScrollableSheet], only its child changes).
class _StopSheet extends StatefulWidget {
  const _StopSheet({
    required this.stopId,
    this.initialStopName,
    this.onFocusVehicle,
    this.initialSize,
    this.onHeightChanged,
  });

  final String stopId;
  final String? initialStopName;
  final void Function(Arrival arrival, DateTime asOf)? onFocusVehicle;

  /// Open at this detent fraction instead of the default half — used to open at
  /// the height the nearby sheet was resting at, so nearby → stop is continuous
  /// (owner acceptance #3: no height jump).
  final double? initialSize;

  /// Reports the sheet's pixel height on layout/drag/snap, so the map's geometry
  /// owner ([mapInsetsFor]) shifts the map up to keep the stop above the sheet
  /// (owner R2 #3: the sheet must feed the camera insets, like the nearby sheet).
  final ValueChanged<double>? onHeightChanged;

  @override
  State<_StopSheet> createState() => _StopSheetState();
}

class _StopSheetState extends State<_StopSheet> {
  // The fleet-card leaf currently shown over the board, or null for the board.
  ({FleetVehicle fleet, String? garageNo, VehicleType type})? _leaf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final leaf = _leaf;
    final viewport = MediaQuery.sizeOf(context).height;
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        widget.onHeightChanged?.call(n.extent * viewport);
        return false;
      },
      child: DraggableScrollableSheet(
      // Unified detents (owner R2 #4): large is NOT fullscreen — a map strip
      // always stays on top. Opens at the nearby sheet's resting height when
      // given, else the half detent.
      initialChildSize:
          (widget.initialSize ?? kSheetHalf).clamp(kSheetPeek, kSheetLarge),
      minChildSize: kSheetPeek,
      maxChildSize: kSheetLarge,
      snap: true,
      snapSizes: const [kSheetPeek, kSheetHalf, kSheetLarge],
      expand: false,
      builder: (context, scrollController) {
        // PointerInterceptor stops taps/double-taps on the sheet from falling
        // through to the MapLibre platform view underneath (which would zoom the
        // map) on web. No-op on mobile.
        return PointerInterceptor(
          // A Material (not a plain coloured Container) so the arrival rows'
          // ListTiles paint their ink splashes on it.
          child: Material(
            color: theme.colorScheme.surface,
            borderRadius: kSheetRadius,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                const SheetDragHandle(bottom: 4),
                if (leaf != null) ...[
                  // Subview: the shared fleet card, with a back arrow returning
                  // to the exact board it came from.
                  SheetBackHeader(
                    title: leaf.fleet.modelName ?? l10n.fleetUnknownModel,
                    onBack: () => setState(() => _leaf = null),
                  ),
                  Expanded(
                    child: FleetModelView(
                      fleet: leaf.fleet,
                      fallbackType: leaf.type,
                      garageNo: leaf.garageNo,
                      scrollController: scrollController,
                    ),
                  ),
                ] else
                  Expanded(
                    child: StopBoard(
                      stopId: widget.stopId,
                      initialStopName: widget.initialStopName,
                      scrollController: scrollController,
                      onClose: () => Navigator.of(context).maybePop(),
                      // Swap to the in-sheet fleet card instead of stacking a
                      // separate modal (owner B#2).
                      onOpenFleetCard: (fleet, garageNo, type) => setState(
                        () => _leaf =
                            (fleet: fleet, garageNo: garageNo, type: type),
                      ),
                      onFocusVehicle: widget.onFocusVehicle == null
                          ? null
                          : (arrival, asOf) {
                              Navigator.of(context).maybePop();
                              widget.onFocusVehicle!.call(arrival, asOf);
                            },
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
