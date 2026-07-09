import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_exceptions.dart';
import '../../domain/models/arrival.dart';
import '../../domain/models/favorite_stop.dart';
import '../../domain/models/route_alert.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'arrival_tile.dart';
import 'empty_state.dart';
import 'route_alerts_strip.dart';

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
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // A faint scrim so the map behind stays legible — this reads as an overlay
    // on the same map, not a new screen.
    barrierColor: Colors.black.withValues(alpha: 0.08),
    builder: (_) => _StopSheet(stopId: stopId, initialStopName: stopName),
  );
}

class _StopSheet extends ConsumerStatefulWidget {
  const _StopSheet({required this.stopId, this.initialStopName});

  final String stopId;
  final String? initialStopName;

  @override
  ConsumerState<_StopSheet> createState() => _StopSheetState();
}

class _StopSheetState extends ConsumerState<_StopSheet> {
  Timer? _refreshTimer;
  String? _lineFilter;

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
    final seconds =
        ref.read(settingsControllerProvider).valueOrNull?.refreshIntervalSeconds ??
        30;
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
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
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
    if (board.serviceStatus == ServiceStatus.unavailable) {
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
    final allLines = {...stopLines, ...arrivingLines}.toList()
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

    final ageSeconds = DateTime.now()
        .toUtc()
        .difference(board.updatedAt.toUtc())
        .inSeconds;
    final isStale = ageSeconds > 90;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                      onSelected: (_) => setState(() => _lineFilter = line),
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
        for (final arrival in visibleArrivals)
          ArrivalTile(
            arrival: arrival,
            etaDeltaMinutes: _etaDelta[_vehKey(arrival)],
          ),
        const SizedBox(height: 12),
      ],
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
