import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:latlong2/latlong.dart' as ll;

import '../../core/api_config.dart';
import '../../core/arrival_grouping.dart';
import '../../core/fleet_matcher.dart';
import '../../core/live_position.dart';
import '../../data/api/api_exceptions.dart';
import '../../domain/models/arrival.dart';
import '../../domain/models/favorite_stop.dart';
import '../../domain/models/route_alert.dart';
import '../../domain/models/stop.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/arrival_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/fleet_model_card.dart';
import '../widgets/live_unavailable_banner.dart';
import '../widgets/live_vehicles_map.dart';
import '../widgets/route_alerts_strip.dart';
import '../widgets/scheduled_group_tile.dart';

class StopScreen extends ConsumerStatefulWidget {
  const StopScreen({super.key, required this.stopId, this.initialStopName});

  final String stopId;
  final String? initialStopName;

  @override
  ConsumerState<StopScreen> createState() => _StopScreenState();
}

class _StopScreenState extends ConsumerState<StopScreen> {
  Timer? _refreshTimer;
  String? _lineFilter;

  /// B4: optional "sort by comfort" instead of the default time order. Only
  /// offered when ≥2 arriving vehicles of different classes are identified.
  bool _sortByComfort = false;

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
    final l10n = AppLocalizations.of(context);
    final board = ref.watch(arrivalsProvider(widget.stopId));
    final stopLocation = ref.watch(stopLocationProvider(widget.stopId)).valueOrNull;
    final isFavoriteAsync = ref.watch(favoritesControllerProvider).maybeWhen(
          data: (favs) => favs.any((f) => f.stopId == widget.stopId),
          orElse: () => false,
        );

    final allAlerts = ref.watch(alertsProvider).valueOrNull ?? const <RouteAlert>[];
    final stopName = board.valueOrNull?.stopName ?? widget.initialStopName ?? '';
    final relevantAlerts = allAlerts.where((a) {
      if (a.isExpired) return false;
      final matchesLine = stopLocation?.lines.any(a.matchesLine) ?? false;
      final matchesStop = a.matchesStopName(stopName);
      return matchesLine || matchesStop;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(board.valueOrNull?.stopName ?? widget.initialStopName ?? ''),
        actions: [
          IconButton(
            icon: Icon(isFavoriteAsync ? Icons.star : Icons.star_outline),
            onPressed: () {
              final notifier = ref.read(favoritesControllerProvider.notifier);
              if (isFavoriteAsync) {
                notifier.remove(widget.stopId);
              } else {
                final name = board.valueOrNull?.stopName ?? widget.initialStopName ?? widget.stopId;
                notifier.add(FavoriteStop(stopId: widget.stopId, name: name));
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(arrivalsProvider(widget.stopId)),
        child: ListView(
          children: [
            RouteAlertsStrip(alerts: relevantAlerts),
            board.when(
              loading: () => EmptyState(icon: Icons.directions_transit_outlined, title: l10n.loadingArrivals),
              error: (err, st) => _errorState(l10n, err),
              data: (b) => _boardBody(context, l10n, b, stopLocation),
            ),
          ],
        ),
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
    return EmptyState(icon: Icons.error_outline, title: l10n.noNetworkTitle, subtitle: l10n.noNetworkSubtitle);
  }

  Widget _boardBody(BuildContext context, AppLocalizations l10n, ArrivalsBoard board, Stop? stopLocation) {
    // See stop_sheet.dart: an outage still has the timetable to show, so the
    // wall is only for a board with genuinely nothing on it. (Both shutters
    // carry their own copy of this build — keep them in step.)
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

    // The filter lists every line the stop serves; lines with no current
    // arrival are shown as muted, disabled chips ("inactive"). See stop_sheet.
    final arrivingLines = board.arrivals.map((a) => a.line).toSet();
    // Only chip non-empty lines — a blank value would render an empty chip (F6).
    final allLines = {...?stopLocation?.lines, ...arrivingLines}
        .where((l) => l.trim().isNotEmpty)
        .toList()
      ..sort(_compareLines);
    final effectiveFilter =
        (_lineFilter != null && arrivingLines.contains(_lineFilter))
        ? _lineFilter
        : null;
    final visibleArrivals = effectiveFilter == null
        ? board.arrivals
        : board.arrivals.where((a) => a.line == effectiveFilter).toList();

    // Fleet-ID (B1–B5): resolve each visible arrival's vehicle. Null catalog
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

    // Pair arrivals with their fleet info, then (optionally) reorder by comfort.
    final order = [for (var i = 0; i < visibleArrivals.length; i++) i];
    if (sortByComfort) {
      order.sort((a, b) {
        final ca = fleetByIndex[a]?.comfortScore ?? -1;
        final cb = fleetByIndex[b]?.comfortScore ?? -1;
        if (ca != cb) return cb.compareTo(ca); // higher comfort first
        return visibleArrivals[a].etaMinutes
            .compareTo(visibleArrivals[b].etaMinutes); // tie-break by time
      });
    }

    // Default (time) order: group by line×direction, drop non-live rows the
    // live vehicles already cover, and fold each group's surviving Scheduled
    // into one cell (arrivals-dedup — see SCHEDULE_FALLBACK_CONTRACT). The
    // comfort sort is a deliberately flat, live-only reorder and stays untouched.
    final groupedEntries = groupArrivals(visibleArrivals);

    // Keep the schedule-derived placeholder rows (junk garage, GPS pinned to
    // this stop) off the map — otherwise they render as a motionless stack on
    // the stop pin. They stay in the arrivals list below regardless.
    final mapVehicles = board.arrivals.where(arrivalHasLivePosition).toList();
    // Nothing live left to draw but arrivals *are* coming: explain the empty map
    // instead of a blank slot (which reads as broken).
    final showNoLiveHint = stopLocation != null && mapVehicles.isEmpty;
    final ageSeconds = DateTime.now().toUtc().difference(board.updatedAt.toUtc()).inSeconds;
    final isStale = ageSeconds > 90; // well past the ~30s refresh cadence — likely a stuck cache

    return Column(
      children: [
        if (board.serviceStatus == ServiceStatus.unavailable)
          const LiveUnavailableBanner(),
        if (stopLocation != null && mapVehicles.isNotEmpty)
          SizedBox(
            height: 220,
            child: LiveVehiclesMap(
              arrivals: mapVehicles,
              stopLocation: ll.LatLng(stopLocation.lat, stopLocation.lon),
            ),
          )
        else if (showNoLiveHint)
          _noLiveVehiclesHint(context, l10n),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            _freshnessLabel(l10n, board.updatedAt),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isStale ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
        if (allLines.length > 1)
          // One horizontally-scrolling row instead of a Wrap: a stop with many
          // lines — e.g. Baćevac's ~22 after the suburban merge — used to wrap
          // into a tall multi-row block that shoved the arrivals list off
          // screen. Mirrors the favourites-carousel pattern (F7): horizontal
          // scroll + edge insets so the first/last chip aren't clipped flush.
          // Few-line stops keep their old look — the row just doesn't scroll.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
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
                      onSelected: (_) => setState(() => _lineFilter = line),
                    )
                  else
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
                  onSelected: (_) => setState(() => _sortByComfort = true),
                ),
              ],
            ),
          ),
        // Comfort sort keeps its flat, per-vehicle list; the default view uses
        // the grouped/deduped/collapsed entries.
        if (sortByComfort)
          for (final i in order) _arrivalTile(context, visibleArrivals[i], fleetByIndex[i])
        else
          for (final entry in groupedEntries)
            switch (entry) {
              ArrivalRow(:final arrival, :final index) =>
                _arrivalTile(context, arrival, fleetByIndex[index]),
              ScheduledGroupCell() => ScheduledGroupTile(cell: entry),
            },
      ],
    );
  }

  /// One live/expected vehicle row, wired to open its fleet card when known.
  Widget _arrivalTile(BuildContext context, Arrival arrival, FleetVehicle? fleet) {
    return ArrivalTile(
      arrival: arrival,
      fleet: fleet,
      onOpenFleetCard: fleet != null && fleet.hasInfo
          ? () => showFleetModelCard(
                context,
                fleet: fleet,
                fallbackType: arrival.vehicleType,
                garageNo: arrival.garageNo,
              )
          : null,
    );
  }

  /// Shown in place of the mini-map when the placeholder filter has left no
  /// genuinely live vehicle to plot — an
  /// explained empty state (the lines are still listed below) instead of a blank
  /// slot that reads as a failure. Same muted-banner language as the route alerts
  /// strip / freshness label.
  Widget _noLiveVehiclesHint(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.location_searching,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.noLiveVehiclesOnMap,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Natural line sort: numeric lines by value (3 before 29), lettered after.
  static int _compareLines(String a, String b) {
    final na = int.tryParse(RegExp(r'^\d+').firstMatch(a)?.group(0) ?? '');
    final nb = int.tryParse(RegExp(r'^\d+').firstMatch(b)?.group(0) ?? '');
    if (na != null && nb != null && na != nb) return na.compareTo(nb);
    if (na != null && nb == null) return -1;
    if (na == null && nb != null) return 1;
    return a.compareTo(b);
  }

  String _freshnessLabel(AppLocalizations l10n, DateTime updatedAt) {
    final seconds = DateTime.now().toUtc().difference(updatedAt.toUtc()).inSeconds;
    if (seconds < 5) return l10n.stopUpdatedJustNow;
    if (seconds < 60) return l10n.stopUpdatedSecondsAgo(seconds);
    return l10n.stopUpdatedMinutesAgo((seconds / 60).round());
  }
}
