import 'package:flutter/material.dart';

import '../../core/arrival_display.dart';
import '../../core/eta_format.dart';
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

  /// Opacity for a non-clickable row (Expected / Scheduled). Brightness is the
  /// single, at-a-glance signal for "can I tap this?" — dim == not tappable.
  static const double _dimOpacity = 0.58;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final status = arrivalRowStatus(arrival);
    // Clickability == live. A dimmed row + missing chevron means "not a vehicle
    // you can follow" (Expected placeholder / Scheduled fallback) without the
    // user having to read the subtitle to find out.
    final clickable = status == ArrivalRowStatus.live;
    final dim = clickable ? 1.0 : _dimOpacity;

    return ListTile(
      onTap: onTap,
      // Match the map's transport palette so a line reads the same colour here
      // as its marker on the map (bus blue, trolley orange, tram red).
      leading: Opacity(
        opacity: dim,
        child: CircleAvatar(
          backgroundColor: vehicleColor(arrival.vehicleType),
          child: vehicleGlyph(
            arrival.vehicleType,
            size: 22,
            color: Colors.white,
          ),
        ),
      ),
      title: Opacity(
        opacity: dim,
        child: Text(arrival.line, style: theme.textTheme.titleMedium),
      ),
      subtitle: _subtitle(context, l10n, status),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: dim,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  etaLabel(l10n, Localizations.localeOf(context).toString(),
                      arrival.etaMinutes),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (etaDeltaMinutes != null && etaDeltaMinutes != 0)
                  _EtaChangeBadge(deltaMinutes: etaDeltaMinutes!),
              ],
            ),
          ),
          // The chevron is the drill-in affordance: only a live vehicle can be
          // opened and followed on the map.
          if (clickable)
            Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }

  /// Second line of the tile: the "N stops away" text and the Fleet-ID badge
  /// strip, kept on a single row so a badge never turns one row into two (B2).
  Widget? _subtitle(BuildContext context, AppLocalizations l10n, ArrivalRowStatus status) {
    final theme = Theme.of(context);
    // A clock + honest status label, so no row renders blank and none pretends
    // to be a tappable live vehicle:
    //   * Scheduled → "Scheduled" (timetable fallback, no vehicle at all).
    //   * Expected  → "Expected"  (valid ETA, no live position yet — the
    //                 placeholder class; reclassification is arrivals-dedup's).
    // The clock keeps its normal muted colour ("as now"); the row-level dimming
    // is applied to the line icon + ETA in build().
    final Widget? statusChip;
    if (status == ArrivalRowStatus.scheduled || status == ArrivalRowStatus.expected) {
      statusChip = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            status == ArrivalRowStatus.scheduled ? l10n.arrivalScheduled : l10n.arrivalExpected,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      );
    } else {
      // Live: describe proximity, but don't trust stops_remaining blindly — the
      // upstream emits 0 as junk for some rows even with a 10-20 min ETA, so
      // "here" would lie. Only show it when it agrees with the ETA.
      final stopsText = switch (arrivalProximity(
        stopsRemaining: arrival.stopsRemaining,
        etaMinutes: arrival.etaMinutes,
      )) {
        ArrivalProximity.here => l10n.arrivalStopsAway(0),
        ArrivalProximity.stopsAway => l10n.arrivalStopsAway(arrival.stopsRemaining!),
        ArrivalProximity.unknown => null,
      };
      statusChip = stopsText == null
          ? null
          : Flexible(child: Text(stopsText, overflow: TextOverflow.ellipsis));
    }
    // Fleet badges belong to a vehicle identified by garage number — present for
    // both live AND expected (placeholder) rows, but never for a scheduled row
    // (no vehicle exists yet), matching the prior behaviour for scheduled.
    final strip = (fleet == null || status == ArrivalRowStatus.scheduled)
        ? null
        : FleetBadgeStrip(
            fleet: fleet!,
            garageNo: arrival.garageNo,
            onTap: fleet!.hasInfo ? onOpenFleetCard : null,
          );
    if (statusChip == null && strip == null) return null;
    return Row(
      children: [
        if (statusChip != null) statusChip,
        if (statusChip != null && strip != null) const SizedBox(width: 10),
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
