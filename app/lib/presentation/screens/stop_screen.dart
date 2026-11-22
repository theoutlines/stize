import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:latlong2/latlong.dart' as ll;

import '../../core/api_config.dart';
import '../../core/arrival_grouping.dart';
import '../../core/design/stize_tokens.dart';
import '../../core/fleet_matcher.dart';
import '../../core/foreground.dart';
import '../../core/live_position.dart';
import '../../data/analytics/event_logger.dart';
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
import '../widgets/jam_stop_banner.dart';
import '../widgets/live_unavailable_banner.dart';
import '../widgets/live_vehicles_map.dart';
import '../widgets/route_alerts_strip.dart';
import '../widgets/scheduled_group_tile.dart';
import '../widgets/stize_filter_chips.dart';

class StopScreen extends ConsumerStatefulWidget {
  const StopScreen({super.key, required this.stopId, this.initialStopName});

  final String stopId;
  final String? initialStopName;

  @override
  ConsumerState<StopScreen> createState() => _StopScreenState();
}

class _StopScreenState extends ConsumerState<StopScreen> {
  Timer? _refreshTimer;
  late final ForegroundResumeListener _resume = ForegroundResumeListener(() {
    if (mounted) _refreshNow();
  });
  String? _lineFilter;

  /// B4: optional "sort by comfort" instead of the default time order. Only
  /// offered when ≥2 arriving vehicles of different classes are identified.
  bool _sortByComfort = false;

  @override
  void initState() {
    super.initState();
    _scheduleRefresh();
    // This full screen is reached only via the /stop/:id route — the "My Stops"
    // (favorites) list and external deep links — so the open is tagged as such.
    // (The in-app tap path uses the bottom sheet, which tags its own source.)
    ref
        .read(eventLoggerProvider)
        .log(Ev.stopOpen, props: {'source': Ev.srcFavorites});
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _resume; // start listening for foreground returns
    _refreshTimer = Timer.periodic(kLiveRefreshInterval, (_) {
      if (appInForeground) _refreshNow();
    });
  }

  void _refreshNow() {
    ref.invalidate(arrivalsProvider(widget.stopId));
    if (ref.read(jamDetectionEnabledProvider)) ref.invalidate(jamsProvider);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _resume.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final board = ref.watch(arrivalsProvider(widget.stopId));
    final stopLocation = ref
        .watch(stopLocationProvider(widget.stopId))
        .valueOrNull;
    final isFavoriteAsync = ref
        .watch(favoritesControllerProvider)
        .maybeWhen(
          data: (favs) => favs.any((f) => f.stopId == widget.stopId),
          orElse: () => false,
        );

    final allAlerts =
        ref.watch(alertsProvider).valueOrNull ?? const <RouteAlert>[];
    final stopName =
        board.valueOrNull?.stopName ?? widget.initialStopName ?? '';
    final relevantAlerts = allAlerts.where((a) {
      if (a.isExpired) return false;
      final matchesLine = stopLocation?.lines.any(a.matchesLine) ?? false;
      final matchesStop = a.matchesStopName(stopName);
      return matchesLine || matchesStop;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          board.valueOrNull?.stopName ?? widget.initialStopName ?? '',
        ),
        actions: [
          IconButton(
            icon: Icon(isFavoriteAsync ? Icons.star : Icons.star_outline),
            onPressed: () {
              final notifier = ref.read(favoritesControllerProvider.notifier);
              if (isFavoriteAsync) {
                notifier.remove(widget.stopId);
              } else {
                final name =
                    board.valueOrNull?.stopName ??
                    widget.initialStopName ??
                    widget.stopId;
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
            JamStopBanner(
              stopId: widget.stopId,
              lines: stopLocation?.lines ?? const [],
            ),
            board.when(
              loading: () => EmptyState(
                icon: Icons.directions_transit_outlined,
                title: l10n.loadingArrivals,
              ),
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
        onRetry: _refreshNow,
        retryLabel: l10n.retry,
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
      onRetry: _refreshNow,
      retryLabel: l10n.retry,
    );
  }

  Widget _boardBody(
    BuildContext context,
    AppLocalizations l10n,
    ArrivalsBoard board,
    Stop? stopLocation,
  ) {
    // See stop_sheet.dart: an outage still has the timetable to show, so the
    // wall is only for a board with genuinely nothing on it. (Both shutters
    // carry their own copy of this build — keep them in step.)
    if (board.serviceStatus == ServiceStatus.unavailable &&
        board.arrivals.isEmpty) {
      return EmptyState(
        icon: Icons.pause_circle_outline,
        title: l10n.serviceKilledTitle,
        subtitle: l10n.serviceKilledSubtitle,
        onRetry: _refreshNow,
        retryLabel: l10n.retry,
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
    final allLines = {
      ...?stopLocation?.lines,
      ...arrivingLines,
    }.where((l) => l.trim().isNotEmpty).toList()..sort(_compareLines);
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
        return visibleArrivals[a].etaMinutes.compareTo(
          visibleArrivals[b].etaMinutes,
        ); // tie-break by time
      });
    }

    // Default (time) order: group by line×direction, drop non-live rows the
    // live vehicles already cover, and fold each group's surviving Scheduled
    // into one cell (arrivals-dedup — see SCHEDULE_FALLBACK_CONTRACT). The
    // comfort sort is a deliberately flat, live-only reorder and stays untouched.
    // One card per line×direction, later vehicles folded into it.
    final groupedEntries = foldLiveByDirection(groupArrivals(visibleArrivals));

    // Keep the schedule-derived placeholder rows (junk garage, GPS pinned to
    // this stop) off the map — otherwise they render as a motionless stack on
    // the stop pin. They stay in the arrivals list below regardless.
    final mapVehicles = board.arrivals.where(arrivalHasLivePosition).toList();
    // Nothing live left to draw but arrivals *are* coming: explain the empty map
    // instead of a blank slot (which reads as broken).
    final showNoLiveHint = stopLocation != null && mapVehicles.isEmpty;
    final ageSeconds = DateTime.now()
        .toUtc()
        .difference(board.updatedAt.toUtc())
        .inSeconds;
    final isStale =
        ageSeconds >
        90; // well past the ~30s refresh cadence — likely a stuck cache

    // Destination (headsign) per direction route_id, from the GTFS line
    // directory. Empty until it loads / offline without a mirror.
    final destinations =
        ref.watch(lineDestinationsProvider).valueOrNull ??
        const <String, String>{};
    // The Stiže card look is live only when the design-system theme is on; OFF
    // keeps the flat ListTile rows with no inter-card gaps (killswitch).
    final stize = StizeColors.of(context);

    // Build the arrival rows, flagging the first live/expected card as emphasis.
    final tiles = <Widget>[];
    var firstCard = true;
    void addTile(Arrival arrival, FleetVehicle? fleet, [List<int> later = const []]) {
      tiles.add(_arrivalTile(
        context,
        arrival,
        fleet,
        stopName: board.stopName,
        destinations: destinations,
        allArrivals: visibleArrivals,
        emphasis: firstCard,
        later: sortByComfort ? null : later,
      ));
      firstCard = false;
    }

    if (sortByComfort) {
      for (final i in order) {
        addTile(visibleArrivals[i], fleetByIndex[i]);
      }
    } else {
      for (final entry in groupedEntries) {
        switch (entry) {
          case ArrivalRow(:final arrival, :final index, :final laterEtaMinutes):
            addTile(arrival, fleetByIndex[index], laterEtaMinutes);
          case ScheduledGroupCell():
            tiles.add(ScheduledGroupTile(cell: entry));
        }
      }
    }

    return Column(
      // Stretch, so the freshness line and the line-chip row start at the same
      // 16px edge as the cards instead of centring on wide screens.
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
              color: isStale
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        if (allLines.length > 1)
          _lineFilterChips(
            context,
            stize,
            allLines,
            arrivingLines,
            effectiveFilter,
            board,
          ),
        if (canSortByComfort)
          // Stiže: the same text chips as "All lines", on the cards' 16px edge.
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
            ],
          ),
        ),
      ],
    );
  }

  /// The line filter — a horizontal scroller (a stop can serve ~22 lines after
  /// the suburban merge). Stiže (flag ON): neutral "All lines" text chip + a
  /// colour-filled chip per line. OFF: the Material ChoiceChips as before.
  Widget _lineFilterChips(
    BuildContext context,
    StizeColors? stize,
    List<String> allLines,
    Set<String> arrivingLines,
    String? effectiveFilter,
    ArrivalsBoard board,
  ) {
    final l10n = AppLocalizations.of(context);
    if (stize == null) {
      return SingleChildScrollView(
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
                  onSelected: (_) {
                    ref.read(eventLoggerProvider).log(Ev.lineFilter);
                    setState(() => _lineFilter = line);
                  },
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
      );
    }

    final typeByLine = stizeTypeByLine(board.arrivals);
    return StizeLineFilterRow(
      allLabel: l10n.lineFilterAll,
      allLines: allLines,
      arrivingLines: arrivingLines,
      typeByLine: typeByLine,
      selected: effectiveFilter,
      onSelect: (line) {
        if (line != null) ref.read(eventLoggerProvider).log(Ev.lineFilter);
        setState(() => _lineFilter = line);
      },
    );
  }

  /// One live/expected vehicle row, wired to open its fleet card when known.
  Widget _arrivalTile(
    BuildContext context,
    Arrival arrival,
    FleetVehicle? fleet, {
    String stopName = '',
    Map<String, String> destinations = const {},
    List<Arrival> allArrivals = const [],
    bool emphasis = false,
    List<int>? later,
  }) {
    return ArrivalTile(
      arrival: arrival,
      fleet: fleet,
      emphasis: emphasis,
      destination: displayDestination(
          destinations[arrival.directionRouteId ?? arrival.routeId],
          stopName,
          AppLocalizations.of(context).arrivalTerminus),
      // Folded card (one per direction): later trips sit under the big ETA,
      // so no "next in" in the caption.
      nextEtaMinutes: later != null ? null : stizeNextEtaForLine(allArrivals, arrival),
      laterEtaMinutes: later ?? const [],
      headwayMinutes: ref
          .watch(stopPlannedHeadwaysProvider(widget.stopId))
          .valueOrNull?[arrival.directionRouteId ?? arrival.routeId],
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
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
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
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
    final seconds = DateTime.now()
        .toUtc()
        .difference(updatedAt.toUtc())
        .inSeconds;
    if (seconds < 5) return l10n.stopUpdatedJustNow;
    if (seconds < 60) return l10n.stopUpdatedSecondsAgo(seconds);
    return l10n.stopUpdatedMinutesAgo((seconds / 60).round());
  }
}
