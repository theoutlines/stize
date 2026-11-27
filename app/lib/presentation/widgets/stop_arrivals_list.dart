import 'package:flutter/material.dart';
import 'package:stize/core/design/stize_text.dart';

import 'animated_entries.dart';
import 'flat_cards.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/arrival_grouping.dart';
import '../../core/design/stize_tokens.dart';
import '../../core/live_position.dart';
import '../../core/movement_tracker.dart';
import '../../data/analytics/event_logger.dart';
import '../../data/api/api_exceptions.dart';
import '../../domain/models/arrival.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'arrival_tile.dart';
import 'empty_state.dart';
import 'live_unavailable_banner.dart';
import 'scheduled_group_tile.dart';
import 'stize_filter_chips.dart';
import 'stize_transit_card.dart';
import 'stretch_card_list.dart';
import '../../core/arrival_display.dart';
import '../../core/design/stize_icons.dart';

/// THE arrivals list of a stop, shared by both shutters: the in-app sheet
/// ([StopBoard]) and the `/stop/:id` deep-link screen ([StopScreen]). Owns the
/// line filter, the line×direction folding, the ETA-change
/// badges and the card wiring, so a change to how arrivals render is made once.
///
/// The hosts keep only their chrome (header / app bar, alerts, jam banner,
/// refresh timer) and pass [aboveFreshness] for anything that sits between the
/// outage banner and the freshness line (the deep-link screen's mini map).
class StopArrivalsList extends ConsumerStatefulWidget {
  const StopArrivalsList({
    super.key,
    required this.stopId,
    required this.board,
    required this.stopLines,
    required this.onRetry,
    this.aboveFreshness,
    this.onFocusVehicle,
  });

  final String stopId;
  final ArrivalsBoard board;

  /// Every line the stop serves (from the stop directory). The filter lists
  /// them all; lines with no current arrival show as muted, disabled chips.
  final List<String> stopLines;

  final VoidCallback onRetry;

  /// Optional block between the outage banner and the freshness line.
  final Widget? aboveFreshness;

  /// Tap on a live row → the host map focuses that vehicle. Null → not tappable.
  final void Function(Arrival arrival, DateTime asOf)? onFocusVehicle;

  @override
  ConsumerState<StopArrivalsList> createState() => _StopArrivalsListState();
}

class _StopArrivalsListState extends ConsumerState<StopArrivalsList> {
  /// Picked lines; empty = "All lines" (see [toggleLineFilter]).
  Set<String> _lineFilter = const {};

  @override
  void initState() {
    super.initState();
    _trackEta(widget.board);
  }

  @override
  void didUpdateWidget(StopArrivalsList old) {
    super.didUpdateWidget(old);
    if (!identical(old.board, widget.board)) _trackEta(widget.board);
  }

  /// Feed every live fix to the shared movement tracker, stamped with the
  /// board's own time: a vehicle whose position stays put for two minutes
  /// reads as stuck (no pulsing dot, "≈" time).
  void _trackEta(ArrivalsBoard board) {
    for (final a in board.arrivals) {
      final gps = a.gps;
      final key = a.garageNo;
      if (gps == null || key == null || !arrivalHasLivePosition(a)) continue;
      MovementTracker.instance.observe(key, gps.lat, gps.lon, at: board.updatedAt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final board = widget.board;

    // "Live unavailable" is not "nothing to show": the timetable comes from our
    // own GTFS bundle, so an outage reads like a night board with a banner. The
    // wall is only honest when there is genuinely nothing.
    if (board.serviceStatus == ServiceStatus.unavailable &&
        board.arrivals.isEmpty) {
      return EmptyState(
        icon: StizeIcons.pause,
        title: l10n.serviceKilledTitle,
        subtitle: l10n.serviceKilledSubtitle,
        onRetry: widget.onRetry,
        retryLabel: l10n.retry,
      );
    }
    if (board.arrivals.isEmpty) {
      return EmptyState(
        icon: StizeIcons.moon,
        title: l10n.emptyArrivalsTitle,
        subtitle: l10n.emptyArrivalsSubtitle,
      );
    }

    // Chips only for lines with an arrival on the board: filtering by a line
    // that isn't coming is a dead end. Non-empty only: a blank value would
    // render an empty chip (F6).
    final chipLines =
        board.arrivals
            .map((a) => a.line)
            .where((l) => l.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort(compareLineNames);

    // A picked line that stops arriving drops out of the filter without
    // mutating state during build; none left = "All lines".
    final effectiveFilter = _lineFilter.where(chipLines.contains).toSet();
    final visibleArrivals = effectiveFilter.isEmpty
        ? board.arrivals
        : board.arrivals
              .where((a) => effectiveFilter.contains(a.line))
              .toList();

    final destinations =
        ref.watch(lineDestinationsProvider).valueOrNull ??
        const <String, String>{};

    final flat = FlatCards.of(context);
    // Live and expected cards first, in time order; the timetable follows in
    // its own section under a "By timetable" header (owner, 2026-11-25: never
    // mix the timetable into the live run).
    final tiles = <Widget>[];
    final timetable = <Widget>[];
    final sc = StizeColors.of(context);
    Color? lastLive;
    Color? lastTimetable;
    {
      // One card per line×direction, later vehicles folded in, covered
      // non-live rows dropped, surviving timetable times folded into a cell.
      // Directions whose headsign is this stop: those vehicles end here.
      const marker = '\u0000';
      final terminating = {
        for (final e in destinations.entries)
          if (displayDestination(e.value, board.stopName, marker) == marker)
            e.key,
      };
      final schedSeen = <String, int>{};
      for (final entry in foldLiveByDirection(
        groupArrivals(visibleArrivals, terminatingDirections: terminating),
      )) {
        switch (entry) {
          case ArrivalRow(:final arrival, :final laterEtaMinutes):
            final dir = arrival.directionRouteId ?? arrival.routeId;
            final status = arrivalRowStatus(arrival);
            lastLive = StizeTransitCard.surfaceFor(
              sc,
              arrival.vehicleType,
              scheduled: status == ArrivalRowStatus.scheduled,
              live: status != ArrivalRowStatus.scheduled,
            );
            tiles.add(
              ArrivalTile(
                // Stable identity for the animated list: one card per
                // line×direction.
                key: ValueKey('row|${arrival.line}|$dir'),
                arrival: arrival,
                destination: _cardDestination(
                  arrival.line,
                  dir,
                  destinations,
                  board.stopName,
                  l10n,
                ),
                laterEtaMinutes: laterEtaMinutes,
                onTap:
                    (!arrivalHasLivePosition(arrival) ||
                        widget.onFocusVehicle == null)
                    ? null
                    : () => widget.onFocusVehicle!(arrival, board.updatedAt),
              ),
            );
          case ScheduledGroupCell():
            final n = schedSeen[entry.line] = (schedSeen[entry.line] ?? 0) + 1;
            final dir = entry.directionKey;
            lastTimetable = StizeTransitCard.surfaceFor(
              sc,
              entry.vehicleType,
              scheduled: true,
              live: false,
            );
            timetable.add(
              ScheduledGroupTile(
                key: ValueKey('sch|${entry.line}|$n'),
                cell: entry,
                destination: dir == null
                    ? null
                    : _cardDestination(
                        entry.line,
                        dir,
                        destinations,
                        board.stopName,
                        l10n,
                      ),
              ),
            );
        }
      }
    }
    if (timetable.isNotEmpty) {
      tiles.add(
        TimetableHeader(key: const ValueKey('timetable'), label: l10n.arrivalByTimetable),
      );
      tiles.addAll(timetable);
    }

    // In a stretching list the last card stretches past the bottom.
    StretchCardEdges.reportLast(context, lastTimetable ?? lastLive);

    final ageSeconds = DateTime.now()
        .toUtc()
        .difference(board.updatedAt.toUtc())
        .inSeconds;
    final isStale = ageSeconds > 90; // well past the 30s cadence: stuck cache

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (board.serviceStatus == ServiceStatus.unavailable)
          const LiveUnavailableBanner(),
        ?widget.aboveFreshness,
        Padding(
          // Reads as the title's subline: tight under the level header.
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            _freshnessLabel(l10n, board.updatedAt),
            style: StizeText.of(context).caption.copyWith(
              color: isStale
                  ? theme.colorScheme.error
                  : theme.colorScheme.outline,
            ),
          ),
        ),
        if (chipLines.length > 1)
          StizeLineFilterRow(
            allLabel: l10n.lineFilterAll,
            lines: chipLines,
            // Chip colour == card colour: the type comes from the arrivals.
            typeByLine: stizeTypeByLine(board.arrivals),
            selected: effectiveFilter,
            onSelect: (line) {
              if (line != null) {
                ref.read(eventLoggerProvider).log(Ev.lineFilter);
              }
              setState(
                () => _lineFilter = toggleLineFilter(effectiveFilter, line),
              );
            },
          ),
        // 4px between the colour cards, with a 16px side gutter.
        Padding(
          // Flat (mobile one-scroll): cards run edge to edge.
          padding: EdgeInsets.fromLTRB(
            flat ? 0 : StizeSpace.space4,
            StizeSpace.space1,
            flat ? 0 : StizeSpace.space4,
            0,
          ),
          // The list ends with its last card (owner, 2026-11-24): the report
          // entry moved to the header's More menu, and the host adds only the
          // safe area below.
          child: AnimatedEntries(
            gap: flat ? 0 : StizeSpace.space1,
            children: tiles,
          ),
        ),
      ],
    );
  }

  /// A vehicle that ends its trip at this stop turns around here: instead of
  /// "→ Terminus" say where it goes next, taken from the line's other
  /// direction on this board ("Then to Zeleni venac" at the airport, owner
  /// 2026-11-23). Falls back to "Terminus" when the board has no other
  /// direction of the line.
  String? _cardDestination(
    String line,
    String dir,
    Map<String, String> destinations,
    String stopName,
    AppLocalizations l10n,
  ) {
    const marker = '\u0000';
    final shown = displayDestination(destinations[dir], stopName, marker);
    if (shown != marker) return shown;
    final board = widget.board;
    for (final a in board.arrivals) {
      if (a.line != line) continue;
      final other = a.directionRouteId ?? a.routeId;
      if (other == dir) continue;
      final next = displayDestination(destinations[other], stopName, marker);
      if (next != null && next != marker && next.trim().isNotEmpty) {
        return l10n.arrivalThenTo(next);
      }
    }
    return l10n.arrivalTerminus;
  }

  String _freshnessLabel(AppLocalizations l10n, DateTime updatedAt) {
    final seconds = DateTime.now()
        .toUtc()
        .difference(updatedAt.toUtc())
        .inSeconds;
    if (seconds < 5) return l10n.stopUpdatedJustNow;
    if (seconds < 60) return l10n.stopUpdatedSecondsAgo(seconds);
    return l10n.stopUpdatedMinutesAgo((seconds / 60).round());
  }
}

/// Natural line sort: numeric lines by value (3 before 29), lettered after.
int compareLineNames(String a, String b) {
  final na = int.tryParse(RegExp(r'^\d+').firstMatch(a)?.group(0) ?? '');
  final nb = int.tryParse(RegExp(r'^\d+').firstMatch(b)?.group(0) ?? '');
  if (na != null && nb != null && na != nb) return na.compareTo(nb);
  if (na != null && nb == null) return -1;
  if (na == null && nb != null) return 1;
  return a.compareTo(b);
}

/// The board's load-error state, shared by both shutters.
Widget stopArrivalsErrorState(
  AppLocalizations l10n,
  Object err,
  VoidCallback onRetry,
) {
  if (err is NotFoundException) {
    return EmptyState(
      icon: StizeIcons.locateOff,
      title: l10n.unknownStopTitle,
      subtitle: l10n.unknownStopSubtitle,
    );
  }
  return EmptyState(
    icon: err is NetworkException ? StizeIcons.offline : StizeIcons.error,
    title: l10n.noNetworkTitle,
    subtitle: l10n.noNetworkSubtitle,
    onRetry: onRetry,
    retryLabel: l10n.retry,
  );
}
