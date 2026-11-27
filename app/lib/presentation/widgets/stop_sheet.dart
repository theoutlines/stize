import 'package:flutter/material.dart';

import '../../core/context_slot.dart';
import '../../domain/models/arrival.dart';
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
    // DS MapSheet: no scrim, the map above stays live.
    barrierColor: Colors.transparent,
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
class _StopSheet extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context).height;
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        onHeightChanged?.call(n.extent * viewport);
        return false;
      },
      child: MapSheetFrame(
        // Opens at the nearby sheet's resting height when given.
        initialSize: initialSize,
        childBuilder: (context, scrollController) => [
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
    );
  }
}
