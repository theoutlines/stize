import 'package:flutter/material.dart';

import '../../core/map_support.dart';
import '../../core/nearby_focus.dart';
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
    // Same rule as the arrivals list: brightness == "leads to a live vehicle you
    // can follow". A schedule-/placeholder-only group reads dimmed and shows no
    // chevron — its tap opens the stop, not a phantom follow.
    final hasLive = nearbyGroupHasLive(group);
    final dim = hasLive ? 1.0 : _dimOpacity;

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
              Opacity(
                opacity: dim,
                child: _LineBadge(line: group.line, type: type, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: dim,
                      child: Text(
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
              // The eta column is NOT dimmed at the group level — each time
              // carries its own status (live bright, scheduled dimmed + clock)
              // so a mixed "live / scheduled" card is legible, and scheduled
              // times earlier than a live one are dropped (visibleNearbyEtas).
              _EtaColumn(etas: visibleNearbyEtas(group)),
              // Drill-in affordance: only a live, followable group gets a chevron.
              if (hasLive)
                Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// Opacity for a non-live Nearby row — matches [ArrivalTile] so both lists
  /// speak the same "dim == not a followable vehicle" language.
  static const double _dimOpacity = 0.58;
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

/// Up to two soonest departures, the first emphasised. Each time carries its
/// own status: a live vehicle reads bright; a scheduled/placeholder time reads
/// dimmed with a small clock, so a mixed card doesn't leave "which time is the
/// bus?" ambiguous.
class _EtaColumn extends StatelessWidget {
  const _EtaColumn({required this.etas});

  final List<NearbyEta> etas;

  static const double _dimOpacity = 0.58;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (etas.isEmpty) {
      return Text('—', style: theme.textTheme.titleMedium);
    }
    String label(NearbyEta e) =>
        e.etaMinutes <= 0 ? l10n.arrivalEtaNow : l10n.arrivalEtaMinutes(e.etaMinutes);

    Widget etaRow(NearbyEta e, TextStyle? style) {
      final live = nearbyEtaIsLive(e);
      return Opacity(
        opacity: live ? 1.0 : _dimOpacity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A clock marks a non-live time so it isn't read as a tracked bus.
            if (!live) ...[
              Icon(Icons.schedule, size: 13, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 3),
            ],
            Text(label(e), style: style),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        etaRow(
          etas.first,
          theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (etas.length > 1)
          etaRow(
            etas[1],
            theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}
