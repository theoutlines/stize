import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/context_slot.dart';
import '../../domain/models/arrival.dart';
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
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // A faint scrim so the map behind stays legible — this reads as an overlay
    // on the same map, not a new screen.
    barrierColor: Colors.black.withValues(alpha: 0.08),
    builder: (_) => _StopSheet(
      stopId: stopId,
      initialStopName: stopName,
      onFocusVehicle: onFocusVehicle,
    ),
  );
}

/// The legacy (flag-OFF) mobile bottom-sheet shell around [StopBoard]: a
/// draggable sheet with a handle. Tapping a live row closes the sheet first,
/// then hands the arrival to the map.
class _StopSheet extends StatelessWidget {
  const _StopSheet({
    required this.stopId,
    this.initialStopName,
    this.onFocusVehicle,
  });

  final String stopId;
  final String? initialStopName;
  final void Function(Arrival arrival, DateTime asOf)? onFocusVehicle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      // Unified detents (owner R2 #4): large is NOT fullscreen — a map strip
      // always stays on top.
      initialChildSize: kSheetHalf,
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
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _handle(theme),
                Expanded(
                  child: StopBoard(
                    stopId: stopId,
                    initialStopName: initialStopName,
                    scrollController: scrollController,
                    onClose: () => Navigator.of(context).maybePop(),
                    onFocusVehicle: onFocusVehicle == null
                        ? null
                        : (arrival, asOf) {
                            Navigator.of(context).maybePop();
                            onFocusVehicle!.call(arrival, asOf);
                          },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _handle(ThemeData theme) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}
