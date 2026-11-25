import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'animated_entries.dart';
import 'flat_cards.dart';

import '../../core/design/stize_icons.dart';
import '../../core/design/stize_tokens.dart';
import '../../core/arrival_display.dart';
import '../../core/eta_format.dart';
import '../../core/movement_tracker.dart';
import '../../core/nearby_focus.dart';
import '../../domain/models/nearby_arrival.dart';
import '../../l10n/app_localizations.dart';
import 'arrival_tile.dart';
import 'scheduled_group_tile.dart';
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
      // Desktop island: hug the cards (no empty strip under the last one).
      shrinkWrap: scrollController == null,
      // Top padding matches the horizontal (side) padding so the first card is
      // inset equally from the island's top and sides (owner desktop request).
      // Flat (mobile one-scroll): edge to edge, no inset.
      // Desktop island (no sheet controller): the last stripe ends at the
      // island's edge, no strip under it (owner, 2026-11-25). The mobile sheet
      // keeps 24 of breathing room above the home indicator.
      // The last stripe ends at the sheet's or the island's edge; only the
      // safe area (home indicator) stays below it. Overscroll stretches and
      // springs back instead of a fixed strip (owner, 2026-11-25).
      padding: flat
          ? EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom)
          : const EdgeInsets.fromLTRB(12, 12, 12, 12),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      children: [
        ?header,
        AnimatedEntries(
          gap: flat ? 0 : StizeSpace.space1,
          children: [
            ..._entries(context, flat),
          ],
        ),
      ],
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh!, child: list);
  }

  /// Live cards first; timetable-only lines after one "By timetable" header,
  /// the same split as a stop board (owner, 2026-11-25). Mobile (flat): one
  /// card per line, its directions swiped inside it.
  List<Widget> _entries(BuildContext context, bool flat) {
    final l10n = AppLocalizations.of(context);
    final out = <Widget>[];
    var headerAdded = false;
    void header(bool live) {
      if (live || headerAdded) return;
      headerAdded = true;
      if (out.isEmpty) return; // all timetable: no header needed
      out.add(
        TimetableHeader(
          key: const ValueKey('timetable'),
          label: l10n.arrivalByTimetable,
        ),
      );
    }

    if (flat) {
      for (final line in carouselByLine(groups)) {
        final live = nearbyGroupHasLive(line.first);
        header(live);
        out.add(
          line.length == 1
              ? NearbyCard(
                  key: ValueKey(line.first.key),
                  group: line.first,
                  onTap: onTapGroup == null
                      ? null
                      : () => onTapGroup!(line.first),
                )
              : LineDirectionsCarousel(
                  key: ValueKey('line|${line.first.line}|$live'),
                  groups: line,
                  onTapGroup: onTapGroup,
                ),
        );
      }
    } else {
      for (final g in groups) {
        header(nearbyGroupHasLive(g));
        out.add(
          NearbyCard(
            key: ValueKey(g.key),
            group: g,
            onTap: onTapGroup == null ? null : () => onTapGroup!(g),
          ),
        );
      }
    }
    return out;
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
    // Live and timetable-only directions never share a card: a live card
    // only swipes to other live directions (owner, 2026-11-25).
    final k = '${g.line}|${nearbyGroupHasLive(g)}';
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

  // Desktop: a trackpad's horizontal swipe arrives as scroll signals, not a
  // drag. Sum them and turn the page once per gesture.
  double _wheelDx = 0;
  DateTime _lastWheelPage = DateTime.fromMillisecondsSinceEpoch(0);
  bool _hover = false;

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final dx = e.scrollDelta.dx;
    if (dx.abs() <= e.scrollDelta.dy.abs()) return; // vertical: the list's
    _wheelDx += dx;
    final now = DateTime.now();
    if (_wheelDx.abs() < 40 ||
        now.difference(_lastWheelPage) < const Duration(milliseconds: 450)) {
      return;
    }
    _lastWheelPage = now;
    final delta = _wheelDx > 0 ? 1 : -1;
    _wheelDx = 0;
    _goTo(_page + delta);
  }

  /// Animate to [target] (the arrows, the dots, a trackpad swipe).
  void _goTo(int target) {
    if (!_has(target) || target == _page || _settle.isAnimating) return;
    final delta = target > _page ? 1 : -1;
    // Jump over pages in between: settle on the neighbour, then land.
    final end = delta > 0 ? -_width : _width;
    _to = Tween<double>(begin: _drag, end: end).animate(
      CurvedAnimation(parent: _settle, curve: StizeMotion.smoothOut),
    )..addListener(() => setState(() => _drag = _to!.value));
    _settle.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _page = target;
        _drag = 0;
      });
    });
  }

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

  Widget _card(int i, {bool sizer = false}) {
    final g = widget.groups[i];
    return NearbyCard(
      key: sizer ? null : ValueKey(g.key),
      group: g,
      onTap: widget.onTapGroup == null ? null : () => widget.onTapGroup!(g),
    );
  }

  Widget _arrow(IconData icon, VoidCallback onTap) => Material(
    color: Colors.black.withValues(alpha: 0.35),
    shape: const CircleBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox.square(
        dimension: 32,
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    ),
  );

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
        final canPrev = _has(_page - 1);
        final canNext = _has(_page + 1);
        final carousel = GestureDetector(
          // Horizontal swipes move the whole card; vertical drags still scroll.
          onHorizontalDragUpdate: _onUpdate,
          onHorizontalDragEnd: _onEnd,
          child: ClipRect(
            child: Stack(
              children: [
                // The tallest direction sets the card's height, so paging
                // never makes the list jump (owner, 2026-11-25).
                for (var i = 0; i < n; i++)
                  IgnorePointer(
                    child: Visibility(
                      visible: false,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: _card(i, sizer: true),
                    ),
                  ),
                Positioned.fill(
                  child: Transform.translate(
                    offset: Offset(_drag, 0),
                    child: _card(_page),
                  ),
                ),
                if (_drag != 0 && _has(side))
                  Positioned.fill(
                    child: Transform.translate(
                      offset: Offset(_drag + (_drag < 0 ? _width : -_width), 0),
                      child: _card(side),
                    ),
                  ),
                // On the centre line of the card's first row (plate | time):
                // 12 padding + half the 40px row, minus the 9px tap inset and
                // half the dot.
                Positioned(
                  top: StizeSpace.space3 + 20 - 9 - 3,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < n; i++)
                        // Each dot opens its direction (a 24px tap box).
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _goTo(i),
                          child: Padding(
                            // Tall tap box, the old 4px gap between dots.
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 9,
                            ),
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(
                                  alpha: i == shown ? 0.95 : 0.4,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Pointer devices: arrows on hover, at the card's sides.
                if (_hover && canPrev)
                  Positioned(
                    left: StizeSpace.space1,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _arrow(StizeIcons.back, () => _goTo(_page - 1)),
                    ),
                  ),
                if (_hover && canNext)
                  Positioned(
                    right: StizeSpace.space1,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _arrow(StizeIcons.forward, () => _goTo(_page + 1)),
                    ),
                  ),
              ],
            ),
          ),
        );
        return Listener(
          onPointerSignal: _onPointerSignal,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: carousel,
          ),
        );
      },
    );
  }
}
