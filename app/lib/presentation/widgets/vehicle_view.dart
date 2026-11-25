import 'package:stize/core/design/stize_tokens.dart';
import 'package:flutter/material.dart';
import 'package:stize/core/design/stize_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fleet_matcher.dart';
import '../../l10n/app_localizations.dart';
import '../../domain/models/vehicle_type.dart';
import '../providers/providers.dart';
import 'follow_view.dart';
import '../../core/design/stize_icons.dart';

/// The body of the follow sheet (mobile) and the follow level of the desktop
/// island, under the [FollowHeader]: the route as a line with stops, then the
/// vehicle itself ("This tram"). One sheet, no separate vehicle card (owner,
/// 2026-11-25).
class VehicleView extends ConsumerWidget {
  const VehicleView({
    super.key,
    required this.line,
    required this.type,
    this.scheduled = false,
    this.garageNo,
    this.route = const [],
    this.vehicleBetween = false,
    this.stuckMinutes,
    this.routeUnavailable = false,
    this.jamAhead = false,
    this.scrollController,
  });

  final String line;
  final VehicleType type;

  /// Opened from a schedule-predicted object (position is a GTFS estimate).
  final bool scheduled;

  /// The followed vehicle's garage number, resolved against the fleet catalog
  /// for the "This tram" card.
  final String? garageNo;

  /// The route around the vehicle: the stop behind it, then the stops ahead.
  final List<FollowRouteStop> route;

  /// The vehicle is between the passed stop and the next one.
  final bool vehicleBetween;

  /// Minutes the vehicle has not moved, once it reads as stuck.
  final int? stuckMinutes;

  /// The followed line has no route geometry in our GTFS (a suburban / non-GSP
  /// carrier): an honest "route unavailable" note instead of the stop list.
  final bool routeUnavailable;

  /// A detected tram jam lies AHEAD of this vehicle on its own direction.
  final bool jamAhead;

  /// The mobile sheet's controller, so dragging the content drags the sheet.
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final catalog = ref.watch(fleetCatalogProvider).valueOrNull;
    final fleet = catalog?.resolve(garageNo);
    // A junk placeholder id (P1..P999) hides the card; a real-but-unmatched
    // garage still shows with what we know.
    final showAbout = fleet != null && fleet.kind != FleetMatchKind.unknownJunk;

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.zero,
      children: [
        if (jamAhead)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: _jamAheadWarning(theme, l10n),
          ),
        if (scheduled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Icon(
                  StizeIcons.clock,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    l10n.vehicleScheduled,
                    style: StizeText.of(
                      context,
                    ).note.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        if (routeUnavailable)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  StizeIcons.info,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.routeUnavailable,
                    style: StizeText.of(
                      context,
                    ).body.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          )
        else if (route.isNotEmpty)
          FollowRoute(
            stops: route,
            line: line,
            type: type,
            vehicleBetween: vehicleBetween,
            stuckMinutes: stuckMinutes,
          ),
        if (showAbout)
          FleetVehicleCard(fleet: fleet, type: type, garageNo: garageNo)
        else
          const SizedBox(height: 24),
      ],
    );
  }

  /// Compact "possible delay ahead" warning (item 5). Shown only when the host
  /// determined a jam is ahead on THIS vehicle's direction. Observation tone,
  /// amber-tinted like the map + banner.
  Widget _jamAheadWarning(ThemeData theme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: (theme.extension<StizeColors>() ?? StizeColors.dark).jam
              .withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              StizeIcons.hourglass,
              size: 15,
              color: theme.colorScheme.onSurface,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.jamFollowAhead,
                style: StizeText.ofTheme(
                  theme,
                ).caption.copyWith(color: theme.colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
