import 'package:flutter/material.dart';

import '../../core/map_support.dart';
import '../../domain/models/arrival.dart';
import '../../l10n/app_localizations.dart';
import 'vehicle_icon.dart';

class ArrivalTile extends StatelessWidget {
  const ArrivalTile({super.key, required this.arrival, this.etaDeltaMinutes});

  final Arrival arrival;

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
      subtitle: arrival.stopsRemaining != null
          ? Text(l10n.arrivalStopsAway(arrival.stopsRemaining!))
          : null,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            arrival.etaMinutes <= 0 ? l10n.arrivalEtaNow : l10n.arrivalEtaMinutes(arrival.etaMinutes),
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (etaDeltaMinutes != null && etaDeltaMinutes != 0)
            _EtaChangeBadge(deltaMinutes: etaDeltaMinutes!),
        ],
      ),
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
