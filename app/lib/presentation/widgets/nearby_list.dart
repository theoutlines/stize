import 'package:flutter/material.dart';

import 'animated_entries.dart';
import 'flat_cards.dart';

import '../../core/design/stize_tokens.dart';
import '../../core/arrival_display.dart';
import '../../core/eta_format.dart';
import '../../core/movement_tracker.dart';
import '../../core/nearby_focus.dart';
import '../../domain/models/nearby_arrival.dart';
import '../../l10n/app_localizations.dart';
import 'arrival_tile.dart';
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
    // Stiže: colour cards 4px apart (owner spec, same as the stop board).
    // Cards animate in and out on a refresh instead of popping (owner,
    // 2026-11-23); the list is short, so one animated column is fine.
    final flat = FlatCards.of(context);
    final list = ListView(
      controller: scrollController,
      // Top padding matches the horizontal (side) padding so the first card is
      // inset equally from the island's top and sides (owner desktop request).
      // Flat (mobile one-scroll): edge to edge, no inset.
      padding: flat
          ? const EdgeInsets.only(bottom: 24)
          : const EdgeInsets.fromLTRB(12, 12, 12, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        ?header,
        AnimatedEntries(
          gap: flat ? 0 : StizeSpace.space1,
          children: [
            // Mobile (flat): one card per line, directions swiped inside it.
            if (flat)
              for (final line in carouselByLine(groups))
                line.length == 1
                    ? NearbyCard(
                        key: ValueKey(line.first.key),
                        group: line.first,
                        onTap: onTapGroup == null
                            ? null
                            : () => onTapGroup!(line.first),
                      )
                    : LineDirectionsCarousel(
                        key: ValueKey('line|${line.first.line}'),
                        groups: line,
                        onTapGroup: onTapGroup,
                      )
            else
              for (final g in groups)
                NearbyCard(
                  key: ValueKey(g.key),
                  group: g,
                  onTap: onTapGroup == null ? null : () => onTapGroup!(g),
                ),
          ],
        ),
      ],
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
    final first = etas.isEmpty ? null : etas.first;
    final scheduled = first != null && !nearbyEtaIsLive(first);
    final later = etas.skip(1).map((e) => e.etaMinutes).take(3).toList();
    final stuck =
        !scheduled && MovementTracker.instance.isStuck(first?.garageNo);

    // Same card as the stop board; the stop and its distance sit under the
    // destination, since Nearby mixes several stops.
    String? position;
    if (first != null && !scheduled) {
      position = switch (arrivalProximity(
        stopsRemaining: first.stopsRemaining,
        etaMinutes: first.etaMinutes,
      )) {
        ArrivalProximity.here => l10n.arrivalStopsAway(0),
        ArrivalProximity.stopsAway => l10n.arrivalStopsAway(
          first.stopsRemaining!,
        ),
        ArrivalProximity.unknown => null,
      };
    }

    return StizeTransitCard(
      type: group.vehicleType,
      line: group.line,
      destination: group.destination,
      leftNote:
          '${group.stopName} · ${l10n.nearbyDistanceMeters(group.distanceMeters)}',
      position: position,
      moving: hasLive && !stuck,
      approximate: stuck,
      etaMinutes: first?.etaMinutes,
      scheduled: scheduled,
      next: scheduled
          ? null
          : ArrivalTile.laterLabel(l10n, localeName, later),
      followUps: scheduled && later.isNotEmpty
          ? later.take(2).map((m) => clockAt(localeName, m)).join(' · ')
          : null,
      live: hasLive,
      onTap: onTap,
    );
  }
}

/// Groups of the same line become one card whose directions are swiped
/// through, with dots on top (owner, 2026-11-23, after Transit). The card
/// sits where the line's soonest direction sits in [groups]; a line with one
/// direction stays a plain card.
List<List<NearbyGroup>> carouselByLine(List<NearbyGroup> groups) {
  final byLine = <String, List<NearbyGroup>>{};
  final order = <String>[];
  for (final g in groups) {
    final k = g.line;
    if (!byLine.containsKey(k)) order.add(k);
    (byLine[k] ??= []).add(g);
  }
  return [for (final k in order) byLine[k]!];
}

/// One line, several directions: a swipeable card with page dots.
class LineDirectionsCarousel extends StatefulWidget {
  const LineDirectionsCarousel({
    super.key,
    required this.groups,
    this.onTapGroup,
  });

  final List<NearbyGroup> groups;
  final void Function(NearbyGroup group)? onTapGroup;

  @override
  State<LineDirectionsCarousel> createState() => _LineDirectionsCarouselState();
}

class _LineDirectionsCarouselState extends State<LineDirectionsCarousel>
    with SingleTickerProviderStateMixin {
  int _page = 0;
  // Horizontal offset of the current card, follows the finger.
  double _drag = 0;
  double _width = 1;
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: StizeMotion.fast,
  );
  Animation<double>? _to;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  bool _has(int i) => i >= 0 && i < widget.groups.length;

  void _onUpdate(DragUpdateDetails d) {
    _settle.stop();
    setState(() {
      final next = _drag + d.delta.dx;
      // Rubber band at the ends: no neighbour to pull in.
      final edge = !_has(_page + (next < 0 ? 1 : -1));
      _drag = edge ? _drag + d.delta.dx * 0.3 : next;
    });
  }

  void _onEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    var target = 0.0;
    var delta = 0;
    if ((_drag < -_width * 0.25 || v < -400) && _has(_page + 1)) {
      target = -_width;
      delta = 1;
    } else if ((_drag > _width * 0.25 || v > 400) && _has(_page - 1)) {
      target = _width;
      delta = -1;
    }
    _to = Tween<double>(begin: _drag, end: target).animate(
      CurvedAnimation(parent: _settle, curve: StizeMotion.smoothOut),
    )..addListener(() => setState(() => _drag = _to!.value));
    _settle.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _page += delta;
        _drag = 0;
      });
    });
  }

  Widget _card(int i) {
    final g = widget.groups[i];
    return NearbyCard(
      key: ValueKey(g.key),
      group: g,
      onTap: widget.onTapGroup == null ? null : () => widget.onTapGroup!(g),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.groups.length;
    _page = _page.clamp(0, n - 1);
    final side = _drag < 0 ? _page + 1 : _page - 1;
    // Dots follow the card that is mostly on screen.
    final shown = _drag.abs() > _width / 2 && _has(side) ? side : _page;
    return LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth;
        return GestureDetector(
          // Horizontal swipes move the whole card; vertical drags still scroll.
          onHorizontalDragUpdate: _onUpdate,
          onHorizontalDragEnd: _onEnd,
          child: ClipRect(
            child: Stack(
              children: [
                Transform.translate(
                  offset: Offset(_drag, 0),
                  child: _card(_page),
                ),
                if (_drag != 0 && _has(side))
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Transform.translate(
                      offset: Offset(_drag + (_drag < 0 ? _width : -_width), 0),
                      child: _card(side),
                    ),
                  ),
                Positioned(
                  top: StizeSpace.space4,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < n; i++)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(
                                alpha: i == shown ? 0.95 : 0.4,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
