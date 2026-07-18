import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fleet_matcher.dart';
import '../../core/map_support.dart' show vehicleColor;
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
    this.showRouteButton = false,
    this.onShowRoute,
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

  /// Mobile keeps the "Show route on map" action (kept 1:1 with today's app);
  /// desktop hides it — the route is always drawn on the panel-side map.
  final bool showRouteButton;
  final VoidCallback? onShowRoute;

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
      onTap: () => showFleetModelCard(
        context,
        fleet: fleet,
        fallbackType: type,
        garageNo: garageNo,
      ),
      child: card,
    );
  }
}
