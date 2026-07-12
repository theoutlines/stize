import 'package:flutter/material.dart';

import '../../core/map_support.dart';
import '../../domain/models/nearby_arrival.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import 'vehicle_icon.dart';

/// The "Nearby" list itself — a pure, scrollable list of line+direction rows.
/// Deliberately independent of the draggable sheet that hosts it (it only takes
/// a [scrollController] so the two can share a scroll), so it can be reused or
/// tested on its own. All grouping/dedup/sorting is done backend-side.
class NearbyList extends StatelessWidget {
  const NearbyList({
    super.key,
    required this.groups,
    this.scrollController,
    this.onRefresh,
    this.onTapGroup,
  });

  final List<NearbyGroup> groups;

  /// Shared with the host sheet so dragging the list expands/collapses it.
  final ScrollController? scrollController;

  /// Pull-to-refresh; wire to the same fetch the 30s auto-refresh uses.
  final Future<void> Function()? onRefresh;

  final void Function(NearbyGroup group)? onTapGroup;

  @override
  Widget build(BuildContext context) {
    final list = ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _NearbyCard(
        group: groups[i],
        onTap: onTapGroup == null ? null : () => onTapGroup!(groups[i]),
      ),
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

class _NearbyCard extends StatelessWidget {
  const _NearbyCard({required this.group, this.onTap});

  final NearbyGroup group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Classify by the well-known Belgrade line sets (as the map does) rather
    // than the feed's per-line type, which mislabels some lines — keeps a line's
    // colour identical to its map marker.
    final type = classifyLine(group.line);
    final color = vehicleColor(type);
    final destination = group.destination;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _LineBadge(line: group.line, type: type, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      // "→ Destination" reads as the travel direction; when the
                      // upstream gave us no terminus, fall back to the line name.
                      destination != null && destination.isNotEmpty
                          ? '→ $destination'
                          : group.line,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${group.stopName} · ${l10n.nearbyDistanceMeters(group.distanceMeters)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _EtaColumn(arrivals: group.arrivals),
            ],
          ),
        ),
      ),
    );
  }
}

/// The coloured route badge: type glyph + line number, matching the map pill.
class _LineBadge extends StatelessWidget {
  const _LineBadge({required this.line, required this.type, required this.color});

  final String line;
  final VehicleType type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      constraints: const BoxConstraints(minWidth: 56),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          vehicleGlyph(type, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            line,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

/// Up to two soonest departures, the first emphasised.
class _EtaColumn extends StatelessWidget {
  const _EtaColumn({required this.arrivals});

  final List<NearbyEta> arrivals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (arrivals.isEmpty) {
      return Text('—', style: theme.textTheme.titleMedium);
    }
    String label(NearbyEta e) =>
        e.etaMinutes <= 0 ? l10n.arrivalEtaNow : l10n.arrivalEtaMinutes(e.etaMinutes);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label(arrivals.first),
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (arrivals.length > 1)
          Text(
            label(arrivals[1]),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
