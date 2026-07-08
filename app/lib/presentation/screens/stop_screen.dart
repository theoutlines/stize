import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:latlong2/latlong.dart' as ll;

import '../../data/api/api_exceptions.dart';
import '../../domain/models/arrival.dart';
import '../../domain/models/favorite_stop.dart';
import '../../domain/models/stop.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/arrival_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/live_vehicles_map.dart';

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

  @override
  void initState() {
    super.initState();
    _scheduleRefresh();
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    final seconds = ref.read(settingsControllerProvider).valueOrNull?.refreshIntervalSeconds ?? 30;
    _refreshTimer = Timer.periodic(Duration(seconds: seconds), (_) {
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
    final isFavoriteAsync = ref.watch(favoritesControllerProvider).maybeWhen(
          data: (favs) => favs.any((f) => f.stopId == widget.stopId),
          orElse: () => false,
        );

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
        child: board.when(
          loading: () => ListView(
            children: [EmptyState(icon: Icons.directions_transit_outlined, title: l10n.loadingArrivals)],
          ),
          error: (err, st) => ListView(
            children: [_errorState(l10n, err)],
          ),
          data: (b) => _boardBody(context, l10n, b, ref.watch(stopLocationProvider(widget.stopId)).valueOrNull),
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
    if (board.serviceStatus == ServiceStatus.unavailable) {
      return ListView(
        children: [
          EmptyState(
            icon: Icons.pause_circle_outline,
            title: l10n.serviceKilledTitle,
            subtitle: l10n.serviceKilledSubtitle,
          ),
        ],
      );
    }

    final lines = board.arrivals.map((a) => a.line).toSet().toList()..sort();
    final visibleArrivals = _lineFilter == null
        ? board.arrivals
        : board.arrivals.where((a) => a.line == _lineFilter).toList();

    if (board.arrivals.isEmpty) {
      return ListView(
        children: [
          EmptyState(
            icon: Icons.nightlight_outlined,
            title: l10n.emptyArrivalsTitle,
            subtitle: l10n.emptyArrivalsSubtitle,
          ),
        ],
      );
    }

    final vehiclesWithGps = board.arrivals.where((a) => a.gps != null).toList();
    final ageSeconds = DateTime.now().toUtc().difference(board.updatedAt.toUtc()).inSeconds;
    final isStale = ageSeconds > 90; // well past the ~30s refresh cadence — likely a stuck cache

    return ListView(
      children: [
        if (stopLocation != null && vehiclesWithGps.isNotEmpty)
          SizedBox(
            height: 220,
            child: LiveVehiclesMap(
              arrivals: vehiclesWithGps,
              stopLocation: ll.LatLng(stopLocation.lat, stopLocation.lon),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            _freshnessLabel(l10n, board.updatedAt),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isStale ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
        if (lines.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(l10n.lineFilterAll),
                  selected: _lineFilter == null,
                  onSelected: (_) => setState(() => _lineFilter = null),
                ),
                for (final line in lines)
                  ChoiceChip(
                    label: Text(line),
                    selected: _lineFilter == line,
                    onSelected: (_) => setState(() => _lineFilter = line),
                  ),
              ],
            ),
          ),
        for (final arrival in visibleArrivals) ArrivalTile(arrival: arrival),
      ],
    );
  }

  String _freshnessLabel(AppLocalizations l10n, DateTime updatedAt) {
    final seconds = DateTime.now().toUtc().difference(updatedAt.toUtc()).inSeconds;
    if (seconds < 5) return l10n.stopUpdatedJustNow;
    if (seconds < 60) return l10n.stopUpdatedSecondsAgo(seconds);
    return l10n.stopUpdatedMinutesAgo((seconds / 60).round());
  }
}
