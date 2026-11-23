import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/arrival_grouping.dart';
import '../../core/design/stize_tokens.dart';
import '../../core/eta_delta.dart';
import '../../core/fleet_matcher.dart';
import '../../core/live_position.dart';
import '../../data/analytics/event_logger.dart';
import '../../data/api/api_exceptions.dart';
import '../../domain/models/arrival.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'arrival_tile.dart';
import 'empty_state.dart';
import 'fleet_model_card.dart';
import 'live_unavailable_banner.dart';
import 'scheduled_group_tile.dart';
import 'stize_filter_chips.dart';
import 'stop_report_sheet.dart';
import '../../core/design/stize_icons.dart';

/// THE arrivals list of a stop, shared by both shutters: the in-app sheet
/// ([StopBoard]) and the `/stop/:id` deep-link screen ([StopScreen]). Owns the
/// line filter, the comfort sort, the line×direction folding, the ETA-change
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
    this.onOpenFleetCard,
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

  /// Host-rendered fleet card (desktop panel / sheet subview). Null → modal.
  final void Function(FleetVehicle fleet, String? garageNo, VehicleType type)?
  onOpenFleetCard;

  @override
  ConsumerState<StopArrivalsList> createState() => _StopArrivalsListState();
}

class _StopArrivalsListState extends ConsumerState<StopArrivalsList> {
  String? _lineFilter;

  /// B4: optional "sort by comfort" instead of the default time order. Only
  /// offered when ≥2 arriving vehicles of different classes are identified.
  bool _sortByComfort = false;

  // ETA-change tracking (G1): the last absolute predicted arrival instant per
  // live vehicle, and the signed whole-minute delta from the latest refresh.
  // Diffing the absolute instant, not the count-down, keeps the badge honest.
  Map<String, DateTime> _prevArrival = {};
  Map<String, int> _etaDelta = {};

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

  void _trackEta(ArrivalsBoard board) {
    final result = diffEtaDeltas(_prevArrival, board);
    _prevArrival = result.arrivalTimes;
    _etaDelta = result.deltas;
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

    final arrivingLines = board.arrivals.map((a) => a.line).toSet();
    // Only chip non-empty lines — a blank value would render an empty chip (F6).
    final allLines = {
      ...widget.stopLines,
      ...arrivingLines,
    }.where((l) => l.trim().isNotEmpty).toList()..sort(compareLineNames);

    // If a filtered line stops arriving, fall back to "all" without mutating
    // state during build.
    final effectiveFilter =
        (_lineFilter != null && arrivingLines.contains(_lineFilter))
        ? _lineFilter
        : null;
    final visibleArrivals = effectiveFilter == null
        ? board.arrivals
        : board.arrivals.where((a) => a.line == effectiveFilter).toList();

    // Fleet-ID (B1–B5). A null catalog silently disables every Fleet surface.
    final catalog = ref.watch(fleetCatalogProvider).valueOrNull;
    final fleetByIndex = <FleetVehicle?>[
      for (final a in visibleArrivals) catalog?.resolve(a.garageNo),
    ];

    // B4 gate: offer the comfort sort only when the identified vehicles span
    // ≥2 distinct classes (a toggle with no effect is worse than none).
    final distinctClasses = <String>{
      for (final f in fleetByIndex)
        if (f != null && f.hasInfo && f.comfortScore != null) f.id ?? '',
    }..remove('');
    final canSortByComfort = distinctClasses.length >= 2;
    final sortByComfort = canSortByComfort && _sortByComfort;

    final destinations =
        ref.watch(lineDestinationsProvider).valueOrNull ??
        const <String, String>{};
    final headways = ref
        .watch(stopPlannedHeadwaysProvider(widget.stopId))
        .valueOrNull;

    final tiles = <Widget>[];
    var firstCard = true; // the nearest arrival reads biggest
    void addTile(Arrival arrival, FleetVehicle? fleet, List<int>? later) {
      final dir = arrival.directionRouteId ?? arrival.routeId;
      tiles.add(
        ArrivalTile(
          arrival: arrival,
          etaDeltaMinutes: _etaDelta[arrival.garageNo],
          fleet: fleet,
          emphasis: firstCard,
          destination: displayDestination(
            destinations[dir],
            board.stopName,
            l10n.arrivalTerminus,
          ),
          // Folded card: later trips sit under the big ETA, so no "next in".
          nextEtaMinutes: later != null
              ? null
              : stizeNextEtaForLine(visibleArrivals, arrival),
          laterEtaMinutes: later ?? const [],
          headwayMinutes: headways?[dir],
          onOpenFleetCard: fleet != null && fleet.hasInfo
              ? () => widget.onOpenFleetCard != null
                    ? widget.onOpenFleetCard!(
                        fleet,
                        arrival.garageNo,
                        arrival.vehicleType,
                      )
                    : showFleetModelCard(
                        context,
                        fleet: fleet,
                        fallbackType: arrival.vehicleType,
                        garageNo: arrival.garageNo,
                      )
              : null,
          onTap:
              (!arrivalHasLivePosition(arrival) ||
                  widget.onFocusVehicle == null)
              ? null
              : () => widget.onFocusVehicle!(arrival, board.updatedAt),
        ),
      );
      firstCard = false;
    }

    if (sortByComfort) {
      // A deliberately flat, live-only reorder: comfort first, time breaks ties.
      final order = [for (var i = 0; i < visibleArrivals.length; i++) i]
        ..sort((a, b) {
          final ca = fleetByIndex[a]?.comfortScore ?? -1;
          final cb = fleetByIndex[b]?.comfortScore ?? -1;
          if (ca != cb) return cb.compareTo(ca);
          return visibleArrivals[a].etaMinutes.compareTo(
            visibleArrivals[b].etaMinutes,
          );
        });
      for (final i in order) {
        addTile(visibleArrivals[i], fleetByIndex[i], null);
      }
    } else {
      // Time order: one card per line×direction, later vehicles folded in,
      // covered non-live rows dropped, surviving Scheduled folded into a cell.
      // Directions whose headsign is this stop: those vehicles end here.
      const marker = '\u0000';
      final terminating = {
        for (final e in destinations.entries)
          if (displayDestination(e.value, board.stopName, marker) == marker)
            e.key,
      };
      for (final entry in foldLiveByDirection(
        groupArrivals(visibleArrivals, terminatingDirections: terminating),
      )) {
        switch (entry) {
          case ArrivalRow(:final arrival, :final index, :final laterEtaMinutes):
            addTile(arrival, fleetByIndex[index], laterEtaMinutes);
          case ScheduledGroupCell():
            tiles.add(ScheduledGroupTile(cell: entry));
        }
      }
    }

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
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
          child: Text(
            _freshnessLabel(l10n, board.updatedAt),
            style: theme.textTheme.bodySmall?.copyWith(
              color: isStale
                  ? theme.colorScheme.error
                  : theme.colorScheme.outline,
            ),
          ),
        ),
        if (allLines.length > 1)
          StizeLineFilterRow(
            allLabel: l10n.lineFilterAll,
            allLines: allLines,
            arrivingLines: arrivingLines,
            // Chip colour == card colour: the type comes from the arrivals.
            typeByLine: stizeTypeByLine(board.arrivals),
            selected: effectiveFilter,
            onSelect: (line) {
              if (line != null) {
                ref.read(eventLoggerProvider).log(Ev.lineFilter);
              }
              setState(() => _lineFilter = line);
            },
          ),
        if (canSortByComfort)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: StizeSpace.space4,
              vertical: StizeSpace.space1,
            ),
            child: Row(
              spacing: StizeSpace.space2,
              children: [
                StizeTextChip(
                  label: l10n.fleetSortByTime,
                  selected: !_sortByComfort,
                  onTap: () => setState(() => _sortByComfort = false),
                ),
                StizeTextChip(
                  label: l10n.fleetSortByComfort,
                  selected: _sortByComfort,
                  onTap: () {
                    ref.read(eventLoggerProvider).log(Ev.sortComfort);
                    setState(() => _sortByComfort = true);
                  },
                ),
              ],
            ),
          ),
        // 4px between the colour cards, with a 16px side gutter.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            StizeSpace.space4,
            StizeSpace.space1,
            StizeSpace.space4,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(height: StizeSpace.space1),
                tiles[i],
              ],
              const SizedBox(height: StizeSpace.space2),
              // The quiet way to flag wrong data: last, never next to arrivals.
              StopReportEntry(stopId: widget.stopId, stopName: board.stopName),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
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
