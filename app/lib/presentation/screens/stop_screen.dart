import 'package:stize/core/design/stize_text.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:latlong2/latlong.dart' as ll;

import '../../core/live_position.dart';
import '../../data/analytics/event_logger.dart';
import '../../domain/models/route_alert.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/stretch_card_list.dart';
import '../widgets/empty_state.dart';
import '../widgets/stop_header_actions.dart';
import '../widgets/stop_arrivals_list.dart';
import '../widgets/jam_stop_banner.dart';
import '../widgets/live_vehicles_map.dart';
import '../widgets/route_alerts_strip.dart';
import '../widgets/stop_live_refresh.dart';
import '../../core/design/stize_icons.dart';

class StopScreen extends ConsumerStatefulWidget {
  const StopScreen({super.key, required this.stopId, this.initialStopName});

  final String stopId;
  final String? initialStopName;

  @override
  ConsumerState<StopScreen> createState() => _StopScreenState();
}

class _StopScreenState extends ConsumerState<StopScreen> with StopLiveRefresh {
  @override
  String get liveStopId => widget.stopId;

  @override
  void initState() {
    super.initState();
    // This full screen is reached only via the /stop/:id route — the "My Stops"
    // (favorites) list and external deep links — so the open is tagged as such.
    // (The in-app tap path uses the bottom sheet, which tags its own source.)
    ref
        .read(eventLoggerProvider)
        .log(Ev.stopOpen, props: {'source': Ev.srcFavorites});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final board = ref.watch(arrivalsProvider(widget.stopId));
    final stopLocation = ref
        .watch(stopLocationProvider(widget.stopId))
        .valueOrNull;

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
        // Star status + More right after the name, as on the in-app board.
        title: Row(
          children: [
            Flexible(child: Text(stopName, overflow: TextOverflow.ellipsis)),
            StopHeaderActions(stopId: widget.stopId, stopName: stopName),
          ],
        ),
      ),
      // The same list as the in-app board (design system: StretchList).
      body: StretchCardList(
        onRefresh: () async {
          ref.invalidate(arrivalsProvider(widget.stopId));
          await ref.read(arrivalsProvider(widget.stopId).future);
        },
        children: [
          RouteAlertsStrip(alerts: relevantAlerts),
          JamStopBanner(
            stopId: widget.stopId,
            lines: stopLocation?.lines ?? const [],
          ),
          board.when(
            loading: () => EmptyState(
              icon: StizeIcons.transit,
              title: l10n.loadingArrivals,
            ),
            error: (err, st) =>
                stopArrivalsErrorState(l10n, err, refreshStopNow),
            data: (b) {
              // Schedule-derived placeholder rows (GPS pinned to this stop)
              // stay off the mini map, or they'd stack on the stop pin.
              final mapVehicles = b.arrivals
                  .where(arrivalHasLivePosition)
                  .toList();
              return StopArrivalsList(
                stopId: widget.stopId,
                board: b,
                stopLines: stopLocation?.lines ?? const [],
                onRetry: refreshStopNow,
                aboveFreshness: stopLocation == null
                    ? null
                    : mapVehicles.isNotEmpty
                    ? SizedBox(
                        height: 220,
                        child: LiveVehiclesMap(
                          arrivals: mapVehicles,
                          stopLocation: ll.LatLng(
                            stopLocation.lat,
                            stopLocation.lon,
                          ),
                        ),
                      )
                    // Nothing live to draw: explain the empty map.
                    : _noLiveVehiclesHint(context, l10n),
              );
            },
          ),
        ],
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              StizeIcons.locate,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.noLiveVehiclesOnMap,
                style: StizeText.of(
                  context,
                ).caption.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
