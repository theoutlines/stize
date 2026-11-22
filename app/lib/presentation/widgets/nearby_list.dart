import 'package:flutter/material.dart';

import '../../core/design/stize_tokens.dart';
import '../../core/eta_format.dart';
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
    this.header,
  });

  final List<NearbyGroup> groups;

  /// Optional banner pinned above the cards but inside the same scroll view (so
  /// the shared drag-to-expand still works) — e.g. the live-unavailable note.
  final Widget? header;

  /// Shared with the host sheet so dragging the list expands/collapses it.
  final ScrollController? scrollController;

  /// Pull-to-refresh; wire to the same fetch the 30s auto-refresh uses.
  final Future<void> Function()? onRefresh;

  final void Function(NearbyGroup group)? onTapGroup;

  @override
  Widget build(BuildContext context) {
    final leading = header == null ? 0 : 1;
    // Stiže: colour cards 4px apart (owner spec, same as the stop board).
    final stize = Theme.of(context).extension<StizeColors>() != null;
    final list = ListView.separated(
      controller: scrollController,
      // Top padding matches the horizontal (side) padding so the first card is
      // inset equally from the island's top and sides (owner desktop request).
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: groups.length + leading,
      separatorBuilder: (_, _) =>
          SizedBox(height: stize ? StizeSpace.space1 : 8),
      itemBuilder: (context, i) {
        if (i < leading) return header!;
        final g = groups[i - leading];
        return NearbyCard(
          group: g,
          onTap: onTapGroup == null ? null : () => onTapGroup!(g),
        );
      },
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

/// One nearby line+direction card. Public so the unified nearby-sheet search can
/// render nearby matches above the global stop/line results (owner C#3) with the
/// exact same card the plain list uses.
class NearbyCard extends StatelessWidget {
  const NearbyCard({super.key, required this.group, this.onTap});

  final NearbyGroup group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Stiže (flag ON): the filled transit-colour card, same language as the
    // stop board's ArrivalTile. OFF: the previous card exactly (killswitch).
    final stize = Theme.of(context).extension<StizeColors>();
    if (stize != null) return _card(context, stize);
    return _legacy(context);
  }

  Widget _card(BuildContext context, StizeColors c) {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final type = group.vehicleType;
    final fill = switch (type) {
      VehicleType.bus => c.transitBus,
      VehicleType.tram => c.transitTram,
      VehicleType.trolleybus => c.transitTrolleybus,
    };
    final on = c.onTransit;
    final hasLive = nearbyGroupHasLive(group);
    final etas = visibleNearbyEtas(group);
    final destination = group.destination;
    final caption = StizeType.caption.copyWith(color: on.withValues(alpha: 0.8));

    // Big ETA: "now" / N + "min" / a clock time when far off. A non-live first
    // time is a timetable time: shown as a quieter clock.
    Widget etaBlock() {
      if (etas.isEmpty) {
        return Text('—', style: StizeType.bigNumber.copyWith(color: on));
      }
      final e = etas.first;
      if (!nearbyEtaIsLive(e)) {
        return Text(
          clockAt(localeName, e.etaMinutes),
          style: StizeType.date.copyWith(
              fontWeight: FontWeight.w400, color: on.withValues(alpha: 0.7)),
        );
      }
      final String value;
      String? unit;
      if (e.etaMinutes <= 0) {
        value = l10n.arrivalEtaNow.toLowerCase();
      } else if (e.etaMinutes >= kFarEtaMinutes) {
        value = clockAt(localeName, e.etaMinutes);
      } else {
        value = '${e.etaMinutes}';
        unit = l10n.arrivalEtaMinutesUnit;
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(value, style: StizeType.bigNumber.copyWith(color: on)),
          if (unit != null) Text(unit, style: caption),
        ],
      );
    }

    // Caption: stop · distance, then the next time of this line with its unit.
    String? next;
    if (etas.length > 1) {
      final m = etas[1].etaMinutes;
      next = m >= kFarEtaMinutes
          ? l10n.arrivalNextAt(clockAt(localeName, m))
          : l10n.arrivalNextIn(m <= 0 ? 0 : m);
    }

    final card = Material(
      color: fill,
      borderRadius: BorderRadius.circular(StizeRadius.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: StizeSpace.space4, vertical: StizeSpace.space3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        vehicleGlyph(type, size: 18, color: on),
                        const SizedBox(width: StizeSpace.space1),
                        Text(group.line,
                            style: StizeType.section
                                .copyWith(fontWeight: FontWeight.w600, color: on)),
                      ],
                    ),
                    if (destination != null && destination.isNotEmpty) ...[
                      const SizedBox(height: StizeSpace.space1),
                      Row(
                        children: [
                          Icon(Icons.arrow_forward_rounded, size: 16, color: on),
                          const SizedBox(width: StizeSpace.space1),
                          Flexible(
                            child: Text(
                              destination,
                              style: StizeType.label.copyWith(color: on),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: StizeSpace.space1),
                    Wrap(
                      spacing: StizeSpace.space2,
                      runSpacing: StizeSpace.space1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (hasLive)
                          Container(
                            width: 6,
                            height: 6,
                            decoration:
                                BoxDecoration(color: on, shape: BoxShape.circle),
                          ),
                        Text(
                          '${group.stopName} · ${l10n.nearbyDistanceMeters(group.distanceMeters)}',
                          style: caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (next != null) Text(next, style: caption),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: StizeSpace.space3),
              etaBlock(),
            ],
          ),
        ),
      ),
    );
    // Brightness == "leads to a live vehicle you can follow" (same as the board).
    return hasLive ? card : Opacity(opacity: 0.82, child: card);
  }

  Widget _legacy(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // The feed's authoritative per-line type (resolved backend-side), the same
    // source the map markers use — so a line's colour matches everywhere.
    final type = group.vehicleType;
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
          vehicleGlyph(type, size: 16, color: StizeColors.of(context).onTransit),
          const SizedBox(width: 6),
          Builder(builder: (context) {
            // Stiže: the line number in a vertical list is the one semibold
            // (StizeType.lineNumber), white on every type. OFF keeps the prior
            // bold 15 (killswitch).
            final stize = Theme.of(context).extension<StizeColors>();
            return Text(
              line,
              style: stize != null
                  ? StizeType.lineNumber.copyWith(color: stize.onTransit)
                  : const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
            );
          }),
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
    final localeName = Localizations.localeOf(context).toString();
    String label(NearbyEta e) => etaLabel(l10n, localeName, e.etaMinutes);

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
