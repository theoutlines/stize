import 'package:flutter/material.dart';

import '../../core/arrival_display.dart';
import '../../core/fleet_matcher.dart';
import '../../core/map_support.dart';
import '../../domain/models/arrival.dart';
import '../../l10n/app_localizations.dart';
import 'fleet_badges.dart';
import 'vehicle_icon.dart';

class ArrivalTile extends StatelessWidget {
  const ArrivalTile({
    super.key,
    required this.arrival,
    this.etaDeltaMinutes,
    this.fleet,
    this.onOpenFleetCard,
    this.onTap,
  });

  final Arrival arrival;

  /// Optional row tap — e.g. to focus this vehicle on the map.
  final VoidCallback? onTap;

  /// Resolved Fleet-ID for this arrival's vehicle, or null when the feature is
  /// off (asset missing/invalid — B5). Drives the compact badges (B2).
  final FleetVehicle? fleet;

  /// Opens the model card (B3). Only wired when [fleet] carries model info.
  final VoidCallback? onOpenFleetCard;

  /// How this line's ETA changed since the previous refresh, in minutes
  /// (positive = now arriving *later*, negative = *sooner*), or null when
  /// unchanged / first seen. Drives the explicit "time changed" badge (G1) so
  /// a silently shifting number doesn't quietly erode trust.
  final int? etaDeltaMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return ListTile(
      onTap: onTap,
      // Match the map's transport palette so a line reads the same colour here
      // as its marker on the map (bus blue, trolley orange, tram red).
      leading: CircleAvatar(
        backgroundColor: vehicleColor(arrival.vehicleType),
        child: vehicleGlyph(
          arrival.vehicleType,
          size: 22,
          color: Colors.white,
        ),
      ),
      title: Text(arrival.line, style: theme.textTheme.titleMedium),
      subtitle: _subtitle(context, l10n),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            arrival.etaMinutes <= 0 ? l10n.arrivalEtaNow : l10n.arrivalEtaMinutes(arrival.etaMinutes),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              // Planned arrivals read dimmer than live ones (they're a fallback,
              // not a tracked vehicle).
              color: arrival.scheduled ? theme.colorScheme.onSurfaceVariant : null,
            ),
          ),
          if (etaDeltaMinutes != null && etaDeltaMinutes != 0)
            _EtaChangeBadge(deltaMinutes: etaDeltaMinutes!),
        ],
      ),
    );
  }

  /// Second line of the tile: the "N stops away" text and the Fleet-ID badge
  /// strip, kept on a single row so a badge never turns one row into two (B2).
  Widget? _subtitle(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    // Planned (timetable) arrival: a clear "по расписанию" marker instead of
    // "N stops away" / fleet badges (which only exist for a live vehicle).
    if (arrival.scheduled) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            l10n.arrivalScheduled,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      );
    }
    // Don't trust stops_remaining blindly: the upstream emits 0 as junk for some
    // rows (placeholder P1..P999 vehicles pinned to the stop) even with a 10-20
    // min ETA — "here" would lie. Only show it when it agrees with the ETA.
    final stopsText = switch (arrivalProximity(
      stopsRemaining: arrival.stopsRemaining,
      etaMinutes: arrival.etaMinutes,
    )) {
      ArrivalProximity.here => l10n.arrivalStopsAway(0),
      ArrivalProximity.stopsAway =>
        l10n.arrivalStopsAway(arrival.stopsRemaining!),
      ArrivalProximity.unknown => null,
    };
    final strip = fleet == null
        ? null
        : FleetBadgeStrip(
            fleet: fleet!,
            garageNo: arrival.garageNo,
            onTap: fleet!.hasInfo ? onOpenFleetCard : null,
          );
    if (stopsText == null && strip == null) return null;
    return Row(
      children: [
        if (stopsText != null)
          Flexible(
            child: Text(stopsText, overflow: TextOverflow.ellipsis),
          ),
        if (stopsText != null && strip != null) const SizedBox(width: 10),
        ?strip,
      ],
    );
  }
}

/// Compact "+N / −N min" badge with an up/down arrow. Later (delayed) reads
/// amber; sooner reads green. The number is language-neutral, so no extra
/// localisation is needed for the glanceable form.
class _EtaChangeBadge extends StatelessWidget {
  const _EtaChangeBadge({required this.deltaMinutes});

  final int deltaMinutes;

  @override
  Widget build(BuildContext context) {
    final later = deltaMinutes > 0;
    final color = later ? const Color(0xFFB25A00) : const Color(0xFF1E7A46);
    final bg = color.withValues(alpha: 0.14);
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            later ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 1),
          Text(
            '${deltaMinutes.abs()} min',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
