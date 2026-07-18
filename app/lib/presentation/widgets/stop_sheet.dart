import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/api_config.dart';
import '../../core/arrival_grouping.dart';
import '../../core/fleet_matcher.dart';
import '../../core/live_position.dart';
import '../../data/analytics/event_logger.dart';
import '../../data/api/api_exceptions.dart';
import '../../domain/models/arrival.dart';
import '../../domain/models/favorite_stop.dart';
import '../../domain/models/route_alert.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'arrival_tile.dart';
import 'empty_state.dart';
import 'fleet_model_card.dart';
import 'live_unavailable_banner.dart';
import 'route_alerts_strip.dart';
import 'scheduled_group_tile.dart';

/// Opens a stop's live arrivals as a bottom sheet *over the current map*, with
/// no screen navigation. This is the seamless replacement for pushing a whole
/// new StopScreen (which spun up a second map and re-drew the attribution): the
/// map stays put behind the sheet and the user can dismiss straight back to it.
///
/// StopScreen still exists for `/stop/:id` deep links; the in-app tap path uses
/// this sheet. The board rendering deliberately mirrors StopScreen's so the two
/// stay consistent.
Future<void> showStopSheet(
  BuildContext context, {
  required String stopId,
  String? stopName,
  void Function(Arrival arrival, DateTime asOf)? onFocusVehicle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // A faint scrim so the map behind stays legible — this reads as an overlay
    // on the same map, not a new screen.
    barrierColor: Colors.black.withValues(alpha: 0.08),
    builder: (_) => _StopSheet(
      stopId: stopId,
      initialStopName: stopName,
      onFocusVehicle: onFocusVehicle,
    ),
  );
}

class _StopSheet extends ConsumerStatefulWidget {
  const _StopSheet({
    required this.stopId,
    this.initialStopName,
    this.onFocusVehicle,
  });

  final String stopId;
  final String? initialStopName;

  /// Called with the tapped arrival (and the board's as-of time, which anchors
  /// its timed-trajectory plan) when its row is selected, so the caller (the
  /// map) can build a guaranteed marker from the arrival's own data (gps +
  /// trajectory + direction), highlight the route and follow the vehicle —
  /// without waiting on an independent viewport fan-out. The sheet closes first.
  final void Function(Arrival arrival, DateTime asOf)? onFocusVehicle;

  @override
  ConsumerState<_StopSheet> createState() => _StopSheetState();
}

class _StopSheetState extends ConsumerState<_StopSheet> {
  Timer? _refreshTimer;
  String? _lineFilter;

  /// B4: optional "sort by comfort" instead of the default time order. Only
  /// offered when ≥2 arriving vehicles of different classes are identified.
  bool _sortByComfort = false;

  // ETA-change tracking (G1): the last ETA we showed per vehicle, and the
  // signed delta from the most recent refresh, so a shifting arrival time is
  // shown *as* a change rather than silently swapped.
  Map<String, int> _prevEta = {};
  Map<String, int> _etaDelta = {};

  static String _vehKey(Arrival a) => a.garageNo ?? '${a.line}-${a.routeId}';

  @override
  void initState() {
    super.initState();
    _scheduleRefresh();
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(kLiveRefreshInterval, (_) {
      ref.invalidate(arrivalsProvider(widget.stopId));
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    // On each refresh, diff the new ETAs against what we last showed (G1).
    ref.listen(arrivalsProvider(widget.stopId), (_, next) {
      final board = next.valueOrNull;
      if (board == null) return;
      final nextPrev = <String, int>{};
      final deltas = <String, int>{};
      for (final a in board.arrivals) {
        final key = _vehKey(a);
        nextPrev[key] = a.etaMinutes;
        final before = _prevEta[key];
        if (before != null && before != a.etaMinutes) {
          deltas[key] = a.etaMinutes - before;
        }
      }
      setState(() {
        _prevEta = nextPrev;
        _etaDelta = deltas;
      });
    });

    final board = ref.watch(arrivalsProvider(widget.stopId));
    final stopLocation = ref
        .watch(stopLocationProvider(widget.stopId))
        .valueOrNull;

    final stopName =
        board.valueOrNull?.stopName ?? widget.initialStopName ?? '';
    final isFavorite = ref
        .watch(favoritesControllerProvider)
        .maybeWhen(
          data: (favs) => favs.any((f) => f.stopId == widget.stopId),
          orElse: () => false,
        );

    final allAlerts =
        ref.watch(alertsProvider).valueOrNull ?? const <RouteAlert>[];
    final relevantAlerts = allAlerts.where((a) {
      if (a.isExpired) return false;
      final matchesLine = stopLocation?.lines.any(a.matchesLine) ?? false;
      return matchesLine || a.matchesStopName(stopName);
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.28,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        // PointerInterceptor stops taps/double-taps on the sheet from falling
        // through to the MapLibre platform view underneath (which would zoom the
        // map) on web. No-op on mobile.
        return PointerInterceptor(
          // A Material (not a plain coloured Container) so the arrival rows'
          // ListTiles paint their ink splashes on it — a bare DecoratedBox
          // background hides them (and trips a debug assertion for a tappable
          // row).
          child: Material(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _handle(theme),
              _header(theme, stopName, isFavorite),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    RouteAlertsStrip(alerts: relevantAlerts),
                    board.when(
                      loading: () => EmptyState(
                        icon: Icons.directions_transit_outlined,
                        title: l10n.loadingArrivals,
                      ),
                      error: (err, _) => _errorState(l10n, err),
                      data: (b) => _boardBody(
                        context,
                        l10n,
                        b,
                        stopLocation?.lines ?? const [],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _handle(ThemeData theme) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: theme.colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _header(ThemeData theme, String stopName, bool isFavorite) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              stopName,
              style: theme.textTheme.titleLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(isFavorite ? Icons.star : Icons.star_outline),
            color: isFavorite ? const Color(0xFFF6A609) : null,
            onPressed: () {
              final notifier = ref.read(favoritesControllerProvider.notifier);
              if (isFavorite) {
                notifier.remove(widget.stopId);
              } else {
                notifier.add(
                  FavoriteStop(stopId: widget.stopId, name: stopName),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _errorState(AppLocalizations l10n, Object err) {
    if (err is NetworkException) {
      return EmptyState(
        icon: Icons.wifi_off_rounded,
        title: l10n.noNetworkTitle,
        subtitle: l10n.noNetworkSubtitle,
      );
    }
    if (err is NotFoundException) {
      return EmptyState(
        icon: Icons.location_off_outlined,
        title: l10n.unknownStopTitle,
        subtitle: l10n.unknownStopSubtitle,
      );
    }
    return EmptyState(
      icon: Icons.error_outline,
      title: l10n.noNetworkTitle,
      subtitle: l10n.noNetworkSubtitle,
    );
  }

  Widget _boardBody(
    BuildContext context,
    AppLocalizations l10n,
    ArrivalsBoard board,
    List<String> stopLines,
  ) {
    // "Live unavailable" is not "nothing to show". The timetable comes from our
    // own GTFS bundle and needs no upstream, so an outage should read like a
    // night board — the same dimmed scheduled rows — with a banner saying why,
    // not a wall. The wall is only honest when there is genuinely nothing: no
    // live, no schedule.
    if (board.serviceStatus == ServiceStatus.unavailable &&
        board.arrivals.isEmpty) {
      return EmptyState(
        icon: Icons.pause_circle_outline,
        title: l10n.serviceKilledTitle,
        subtitle: l10n.serviceKilledSubtitle,
      );
    }
    if (board.arrivals.isEmpty) {
      return EmptyState(
        icon: Icons.nightlight_outlined,
        title: l10n.emptyArrivalsTitle,
        subtitle: l10n.emptyArrivalsSubtitle,
      );
    }

    // Lines currently arriving are "active"; the filter still lists *every*
    // line the stop serves (union with the stop's route list), so an inactive
    // line shows as a muted, disabled chip rather than disappearing.
    final arrivingLines = board.arrivals.map((a) => a.line).toSet();
    // Only chip non-empty lines — a blank value would render an empty chip (F6).
    final allLines = {...stopLines, ...arrivingLines}
        .where((l) => l.trim().isNotEmpty)
        .toList()
      ..sort(_compareLines);

    // If a filtered line stops arriving, fall back to "all" without mutating
    // state during build.
    final effectiveFilter =
        (_lineFilter != null && arrivingLines.contains(_lineFilter))
        ? _lineFilter
        : null;
    final visibleArrivals = effectiveFilter == null
        ? board.arrivals
        : board.arrivals.where((a) => a.line == effectiveFilter).toList();

    // Fleet-ID (B1–B5): resolve each visible arrival's vehicle. A null catalog
    // (asset missing/invalid) silently disables every Fleet-ID surface.
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

    final order = [for (var i = 0; i < visibleArrivals.length; i++) i];
    if (sortByComfort) {
      order.sort((a, b) {
        final ca = fleetByIndex[a]?.comfortScore ?? -1;
        final cb = fleetByIndex[b]?.comfortScore ?? -1;
        if (ca != cb) return cb.compareTo(ca); // higher comfort first
        return visibleArrivals[a]
            .etaMinutes
            .compareTo(visibleArrivals[b].etaMinutes); // tie-break by time
      });
    }

    // Default (time) order: group by line×direction, suppress the non-live rows
    // the live vehicles already cover, and fold each group's surviving Scheduled
    // into one cell (arrivals-dedup). This sheet is the in-app tap path, so the
    // grouping must live here too — StopScreen (deep-link route) mirrors it. The
    // comfort sort stays a deliberately flat, live-only reorder.
    final groupedEntries = groupArrivals(visibleArrivals);

    final ageSeconds = DateTime.now()
        .toUtc()
        .difference(board.updatedAt.toUtc())
        .inSeconds;
    final isStale = ageSeconds > 90;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (board.serviceStatus == ServiceStatus.unavailable)
          const LiveUnavailableBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            _freshnessLabel(l10n, board.updatedAt),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isStale
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        if (allLines.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(l10n.lineFilterAll),
                  selected: effectiveFilter == null,
                  onSelected: (_) => setState(() => _lineFilter = null),
                ),
                for (final line in allLines)
                  if (arrivingLines.contains(line))
                    ChoiceChip(
                      label: Text(line),
                      selected: effectiveFilter == line,
                      onSelected: (_) {
                        ref.read(eventLoggerProvider).log(Ev.lineFilter);
                        setState(() => _lineFilter = line);
                      },
                    )
                  else
                    // Inactive: no arrivals right now — muted and non-clickable.
                    Opacity(
                      opacity: 0.4,
                      child: ChoiceChip(
                        label: Text(line),
                        selected: false,
                        onSelected: null,
                      ),
                    ),
              ],
            ),
          ),
        if (canSortByComfort)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text(l10n.fleetSortByTime),
                  selected: !_sortByComfort,
                  onSelected: (_) => setState(() => _sortByComfort = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  avatar: Icon(Icons.chair_outlined,
                      size: 18,
                      color: _sortByComfort
                          ? Theme.of(context).colorScheme.onSecondaryContainer
                          : Theme.of(context).colorScheme.outline),
                  label: Text(l10n.fleetSortByComfort),
                  selected: _sortByComfort,
                  onSelected: (_) {
                    ref.read(eventLoggerProvider).log(Ev.sortComfort);
                    setState(() => _sortByComfort = true);
                  },
                ),
              ],
            ),
          ),
        // Comfort sort keeps its flat, per-vehicle list; the default view uses
        // the grouped/deduped/collapsed entries.
        if (sortByComfort)
          for (final i in order)
            _arrivalTile(context, board, visibleArrivals[i], fleetByIndex[i])
        else
          for (final entry in groupedEntries)
            switch (entry) {
              ArrivalRow(:final arrival, :final index) =>
                _arrivalTile(context, board, arrival, fleetByIndex[index]),
              ScheduledGroupCell() => ScheduledGroupTile(cell: entry),
            },
        const SizedBox(height: 12),
      ],
    );
  }

  /// One live/expected vehicle row: Fleet card when known, and (for a live row)
  /// tap → close the sheet and hand the whole arrival to the map so it can
  /// guarantee a marker, highlight the route and follow. Placeholder/scheduled
  /// rows aren't tappable (no real fix to follow).
  Widget _arrivalTile(
    BuildContext context,
    ArrivalsBoard board,
    Arrival arrival,
    FleetVehicle? fleet,
  ) {
    return ArrivalTile(
      arrival: arrival,
      etaDeltaMinutes: _etaDelta[_vehKey(arrival)],
      fleet: fleet,
      onOpenFleetCard: fleet != null && fleet.hasInfo
          ? () => showFleetModelCard(
                context,
                fleet: fleet,
                fallbackType: arrival.vehicleType,
                garageNo: arrival.garageNo,
              )
          : null,
      onTap: (!arrivalHasLivePosition(arrival) || widget.onFocusVehicle == null)
          ? null
          : () {
              Navigator.of(context).maybePop();
              widget.onFocusVehicle!.call(arrival, board.updatedAt);
            },
    );
  }

  // Sort lines naturally: numeric lines by value (3 before 29), lettered lines
  // (EKO2, etc.) after the numbers.
  static int _compareLines(String a, String b) {
    final na = int.tryParse(RegExp(r'^\d+').firstMatch(a)?.group(0) ?? '');
    final nb = int.tryParse(RegExp(r'^\d+').firstMatch(b)?.group(0) ?? '');
    if (na != null && nb != null && na != nb) return na.compareTo(nb);
    if (na != null && nb == null) return -1;
    if (na == null && nb != null) return 1;
    return a.compareTo(b);
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
