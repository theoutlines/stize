import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/context_slot.dart';
import '../../core/vehicle_route.dart';
import '../../domain/models/route_shape.dart';
import '../../domain/models/stop.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import '../screens/map_screen_args.dart';
import 'sheet_chrome.dart';
import 'vehicle_icon.dart';

/// Slides up a Yandex-style detail panel for a tapped live vehicle: line +
/// direction, movement state, and the ordered list of upcoming stops with
/// approximate ETAs (all derived from our own data — see [planVehicleRoute]).
Future<void> showVehicleDetailSheet(
  BuildContext context, {
  required String line,
  required VehicleType type,
  required Color color,
  required bool stuck,
  required RouteShape shape,
  required VehicleRoutePlan plan,
}) {
  return showAppSheet<void>(
    context,
    builder: (context) => _VehicleDetailSheet(
      line: line,
      type: type,
      color: color,
      stuck: stuck,
      shape: shape,
      plan: plan,
    ),
  );
}

class _VehicleDetailSheet extends StatelessWidget {
  const _VehicleDetailSheet({
    required this.line,
    required this.type,
    required this.color,
    required this.stuck,
    required this.shape,
    required this.plan,
  });

  final String line;
  final VehicleType type;
  final Color color;
  final bool stuck;
  final RouteShape shape;
  final VehicleRoutePlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    // Same chrome + detents as the nearby / stop sheets (owner acceptance #3):
    // full width, shared drag handle + radius, one draggable scroll view.
    return DraggableScrollableSheet(
      initialChildSize: kSheetHalf,
      minChildSize: kSheetPeek,
      maxChildSize: kSheetLarge,
      snap: true,
      snapSizes: const [kSheetPeek, kSheetHalf, kSheetLarge],
      expand: false,
      builder: (context, scrollController) {
        return PointerInterceptor(
          child: Material(
            color: theme.colorScheme.surface,
            borderRadius: kSheetRadius,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                const SheetDragHandle(bottom: 4),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Row(
                          children: [
                            _pill(),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${shape.origin} → ${shape.destination}',
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _statusChip(context, l10n),
                      ),
                      const SizedBox(height: 8),
                      if (plan.nextStop != null)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.my_location, size: 20),
                          title: Text(plan.nextStop!.name),
                          subtitle: Text(l10n.vehicleNextStop),
                        ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          l10n.vehicleUpcomingStops,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                      for (final u in plan.stops) _stopRow(context, l10n, u),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: Text(
                          l10n.vehicleEtaApprox,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            icon: const Icon(Icons.map_outlined),
                            label: Text(l10n.vehicleShowRoute),
                            onPressed: () => _showRoute(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          vehicleGlyph(type, size: 16, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            line,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final stuckColor = theme.colorScheme.error;
    final movingColor = const Color(0xFF2E9E5B);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          stuck ? Icons.warning_amber_rounded : Icons.directions_run,
          size: 16,
          color: stuck ? stuckColor : movingColor,
        ),
        const SizedBox(width: 6),
        Text(
          stuck ? l10n.vehicleStuck : l10n.vehicleMoving,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: stuck ? stuckColor : movingColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _stopRow(BuildContext context, AppLocalizations l10n, UpcomingStop u) {
    final theme = Theme.of(context);
    final eta = u.etaMinutes;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(
        u.isBoardStop ? Icons.star : Icons.circle,
        size: u.isBoardStop ? 16 : 8,
        color: u.isBoardStop ? theme.colorScheme.primary : theme.colorScheme.outline,
      ),
      title: Text(
        u.stop.name,
        style: u.isBoardStop
            ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)
            : theme.textTheme.bodyMedium,
      ),
      subtitle: u.isBoardStop ? Text(l10n.vehicleYourStop) : null,
      trailing: eta == null
          ? null
          : Text(
              eta <= 0 ? l10n.arrivalEtaNow : l10n.vehicleEtaMinutesApprox(eta),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: u.isBoardStop ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
    );
  }

  void _showRoute(BuildContext context) {
    final routeStops = [
      for (final s in shape.stops)
        Stop(
          stopId: s.stopId,
          name: s.name,
          lat: s.lat,
          lon: s.lon,
          lines: [line],
        ),
    ];
    Navigator.of(context).pop();
    context.push(
      '/map',
      extra: MapScreenArgs(
        stops: routeStops,
        polyline: shape.polyline,
        title: '$line: ${shape.origin} → ${shape.destination}',
        lineNumber: line,
      ),
    );
  }
}
