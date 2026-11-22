import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:latlong2/latlong.dart' as ll;

import '../../core/api_config.dart';
import '../../core/foreground.dart';
import '../../core/live_position.dart';
import '../../data/analytics/event_logger.dart';
import '../../domain/models/favorite_stop.dart';
import '../../domain/models/route_alert.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/stop_arrivals_list.dart';
import '../widgets/jam_stop_banner.dart';
import '../widgets/live_vehicles_map.dart';
import '../widgets/route_alerts_strip.dart';

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
              error: (err, st) =>
                  stopArrivalsErrorState(l10n, err, _refreshNow),
              data: (b) {
                // Schedule-derived placeholder rows (GPS pinned to this stop)
                // stay off the mini map, or they'd stack on the stop pin.
                final mapVehicles =
                    b.arrivals.where(arrivalHasLivePosition).toList();
                return StopArrivalsList(
                  stopId: widget.stopId,
                  board: b,
                  stopLines: stopLocation?.lines ?? const [],
                  onRetry: _refreshNow,
                  aboveFreshness: stopLocation == null
                      ? null
                      : mapVehicles.isNotEmpty
                          ? SizedBox(
                              height: 220,
                              child: LiveVehiclesMap(
                                arrivals: mapVehicles,
                                stopLocation: ll.LatLng(
                                    stopLocation.lat, stopLocation.lon),
                              ),
                            )
                          // Nothing live to draw: explain the empty map.
                          : _noLiveVehiclesHint(context, l10n),
                );
              },
            ),
          ],
        ),
      ),
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
}
