import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fleet_matcher.dart';
import '../../core/map_support.dart' show vehicleColor;
import '../../core/vehicle_route.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'fleet_badges.dart';
import 'fleet_model_card.dart';
import 'vehicle_icon.dart';

/// The reusable "vehicle" view — the content of the followed-vehicle context,
/// hosted identically by the desktop context panel and the mobile follow sheet.
/// Only the container adds chrome (the line pill + back-chip + × live in the
/// panel/sheet header).
///
/// Faithful to the accepted mock's essentials and the owner's decision #7: the
/// direction, a movement-status line, and an "About the vehicle" Fleet-ID card
/// whose behaviour comes straight from the code — a model + garage number +
/// amenity strip; a real-but-unmatched garage shows muted; a junk placeholder
/// hides the card. The per-stop ETA route list from the mock is intentionally
/// left to the map (the highlighted route + stops), since the mock's ETAs were
/// declared placeholders and follow mode has no per-stop plan.
class VehicleView extends ConsumerWidget {
  const VehicleView({
    super.key,
    required this.line,
    required this.type,
    this.origin,
    this.destination,
    this.stuck = false,
    this.scheduled = false,
    this.garageNo,
    this.upcomingStops = const [],
    this.routeUnavailable = false,
    this.showRouteButton = false,
    this.onShowRoute,
    this.onOpenModel,
  });

  final String line;
  final VehicleType type;

  /// Route terminals, once the shape has loaded (null until then).
  final String? origin;
  final String? destination;

  /// "Looks stopped" vs "On the move".
  final bool stuck;

  /// Opened from a schedule-predicted object (position is a GTFS estimate).
  final bool scheduled;

  /// The followed vehicle's garage number (the follow key when it came from an
  /// arrival). Resolved against the fleet catalog for the "About" card.
  final String? garageNo;

  /// The vehicle's upcoming stops (next → end), for the worded route list under
  /// the fleet card. Empty → the list is hidden.
  final List<UpcomingStop> upcomingStops;

  /// The followed line has no route geometry in our GTFS (a suburban / non-GSP
  /// carrier): show an honest "route unavailable" note instead of the stop list.
  final bool routeUnavailable;

  /// Mobile keeps the "Show route on map" action (kept 1:1 with today's app);
  /// desktop hides it — the route is always drawn on the panel-side map.
  final bool showRouteButton;
  final VoidCallback? onShowRoute;

  /// When set, tapping the "About the vehicle" card opens the model as a leaf
  /// sub-view of THIS panel (desktop) instead of a modal. Null → the modal
  /// ([showFleetModelCard], mobile).
  final void Function(FleetVehicle fleet)? onOpenModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(fleetCatalogProvider).valueOrNull;
    final fleet = catalog?.resolve(garageNo);
    // Decision #7: a junk placeholder id (P1..P999) hides the card entirely; a
    // real-but-unmatched garage still shows (muted); a match shows in full.
    final showAbout = fleet != null && fleet.kind != FleetMatchKind.unknownJunk;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        // Direction (route terminals) — the panel/sheet header already carries
        // the line pill, so here we lead with where it's going.
        Text(
          (origin != null && destination != null)
              ? '$origin → $destination'
              : l10n.followingVehicle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _statusChip(theme, l10n),
        _jamAheadWarning(context, ref, theme, l10n),
        if (scheduled) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  l10n.vehicleScheduled,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
        if (showAbout) ...[
          const SizedBox(height: 16),
          _aboutVehicle(context, theme, l10n, fleet),
        ],
        if (routeUnavailable) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.routeUnavailable,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ] else if (upcomingStops.isNotEmpty) ...[
          const SizedBox(height: 16),
          _routeList(context, theme, l10n),
        ],
        if (showRouteButton) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.map_outlined),
              label: Text(l10n.vehicleShowRoute),
              onPressed: onShowRoute,
            ),
          ),
        ],
      ],
    );
  }

  /// Compact "possible delay ahead" warning when the followed vehicle's line has
  /// an active jam (item 5). Observation tone, amber-tinted like the map + banner.
  /// Flag- and feed-health-gated (activeJams is empty when the feed is starving).
  Widget _jamAheadWarning(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    if (!ref.watch(jamDetectionEnabledProvider)) return const SizedBox.shrink();
    final board = ref.watch(jamsProvider).valueOrNull;
    if (board == null || board.jamsForLine(line).isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE8A317).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.hourglass_bottom, size: 15, color: theme.colorScheme.onSurface),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.jamFollowAhead,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The worded route (owner R1 #5): the vehicle's next stop + the ones ahead,
  /// like a running timetable, so you can tell where it's going without staring
  /// at the map. The next (nearest) stop is highlighted. ETAs are approximate
  /// (only the board stop's is a real prediction — the rest are extrapolated).
  Widget _routeList(BuildContext context, ThemeData theme, AppLocalizations l10n) {
    // Cap the list so the panel stays glanceable; the map shows the full route.
    final shown = upcomingStops.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.vehicleUpcomingStops,
          style: theme.textTheme.labelLarge
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < shown.length; i++)
          _routeRow(theme, l10n, shown[i], isNext: i == 0),
      ],
    );
  }

  Widget _routeRow(
      ThemeData theme, AppLocalizations l10n, UpcomingStop u, {required bool isNext}) {
    final eta = u.etaMinutes;
    final color = isNext ? theme.colorScheme.primary : theme.colorScheme.outline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(isNext ? Icons.my_location : Icons.circle,
              size: isNext ? 15 : 7, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              u.stop.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: isNext
                  ? theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700)
                  : theme.textTheme.bodyMedium,
            ),
          ),
          if (u.isBoardStop) ...[
            const SizedBox(width: 6),
            Text(l10n.vehicleYourStop,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.primary)),
          ],
          if (eta != null) ...[
            const SizedBox(width: 8),
            Text(
              eta <= 0 ? l10n.arrivalEtaNow : l10n.vehicleEtaMinutesApprox(eta),
              style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isNext ? FontWeight.w700 : FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(ThemeData theme, AppLocalizations l10n) {
    final stuckColor = theme.colorScheme.error;
    const movingColor = Color(0xFF2E9E5B);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(stuck ? Icons.warning_amber_rounded : Icons.directions_run,
            size: 16, color: stuck ? stuckColor : movingColor),
        const SizedBox(width: 6),
        Text(
          stuck ? l10n.vehicleStuck : l10n.vehicleMoving,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: stuck ? stuckColor : movingColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// "About the vehicle" (decision #7): the Fleet-ID card, priority-2 (below
  /// the route/direction). Tappable → the existing model view. Behaviour is
  /// delegated to [FleetBadgeStrip]: junk placeholder hides, unknown shows muted
  /// garage, a match shows the amenity strip.
  Widget _aboutVehicle(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    FleetVehicle fleet,
  ) {
    final title = fleet.hasInfo && fleet.modelName != null
        ? fleet.modelName!
        : (garageNo == null || garageNo!.trim().isEmpty
            ? l10n.followingVehicle
            : l10n.fleetVehicleNumber(garageNo!));
    final tappable = fleet.hasInfo;

    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.aboutVehicle,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: vehicleColor(type).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: vehicleGlyph(type, size: 18, color: vehicleColor(type)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis),
                    if (garageNo != null &&
                        garageNo!.trim().isNotEmpty &&
                        fleet.hasInfo)
                      Text(
                        l10n.fleetVehicleNumber(garageNo!),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                  ],
                ),
              ),
              // The amenity strip encodes decision #7 exactly (junk → nothing,
              // unknown → muted garage, match → badges).
              FleetBadgeStrip(fleet: fleet, garageNo: garageNo),
            ],
          ),
          if (tappable) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${l10n.viewModelDetails} ›',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
          ],
        ],
      ),
    );

    if (!tappable) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      // Desktop panel: open the model as a leaf sub-view IN the panel (no second
      // surface — owner R1 #3). Mobile: the modal card.
      onTap: () => onOpenModel != null
          ? onOpenModel!(fleet)
          : showFleetModelCard(
              context,
              fleet: fleet,
              fallbackType: type,
              garageNo: garageNo,
            ),
      child: card,
    );
  }
}
