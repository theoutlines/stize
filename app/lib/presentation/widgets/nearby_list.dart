import 'package:flutter/material.dart';

import '../../core/design/stize_tokens.dart';
import '../../core/eta_format.dart';
import '../../core/nearby_focus.dart';
import '../../domain/models/nearby_arrival.dart';
import '../../l10n/app_localizations.dart';
import 'stize_transit_card.dart';

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
    final list = ListView.separated(
      controller: scrollController,
      // Top padding matches the horizontal (side) padding so the first card is
      // inset equally from the island's top and sides (owner desktop request).
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: groups.length + leading,
      separatorBuilder: (_, _) => const SizedBox(height: StizeSpace.space1),
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
    return _card(context, StizeColors.of(context));
  }

  Widget _card(BuildContext context, StizeColors c) {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final hasLive = nearbyGroupHasLive(group);
    final etas = visibleNearbyEtas(group);
    final scheduled = etas.isNotEmpty && !nearbyEtaIsLive(etas.first);
    final caption = StizeTransitCard.captionStyle(c, scheduled: scheduled);

    // The next time of this line, with its unit attached (same as the board).
    String? next;
    if (etas.length > 1) {
      final m = etas[1].etaMinutes;
      next = m >= kFarEtaMinutes
          ? l10n.arrivalNextAt(clockAt(localeName, m))
          : l10n.arrivalNextIn(m <= 0 ? 0 : m);
    }

    return StizeTransitCard(
      type: group.vehicleType,
      line: group.line,
      destination: group.destination,
      caption: [
        if (hasLive) StizeTransitCard.liveDot(c),
        Text(
          '${group.stopName} · ${l10n.nearbyDistanceMeters(group.distanceMeters)}',
          style: caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (next != null) Text(next, style: caption),
      ],
      etaMinutes: etas.isEmpty ? null : etas.first.etaMinutes,
      scheduled: scheduled,
      live: hasLive,
      onTap: onTap,
    );
  }
}
