import 'package:flutter/material.dart';

import '../../core/arrival_grouping.dart';
import '../../core/design/stize_tokens.dart';
import '../../core/eta_format.dart';
import '../../core/map_support.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import 'vehicle_icon.dart';

/// The collapsed schedule fallback for one line×direction: a single row that
/// replaces the N Scheduled rows the fallback used to spray. It shows the
/// nearest ETA large plus up to two follow-ups small/muted — a glance at the
/// picture, not the full timetable.
///
/// Presented as `scheduled` throughout (dimmed, no chevron, not tappable):
/// brightness == clickability, and "по графику ≠ приедет" — no live mimicry.
class ScheduledGroupTile extends StatelessWidget {
  const ScheduledGroupTile({super.key, required this.cell});

  final ScheduledGroupCell cell;

  /// Same dim as a non-clickable [ArrivalTile] row — the single at-a-glance
  /// "you can't tap this" signal.
  static const double _dimOpacity = 0.58;

  @override
  Widget build(BuildContext context) {
    // The Stiže card is live only when the design-system theme is on; OFF keeps
    // the previous dimmed ListTile (killswitch).
    final stize = Theme.of(context).extension<StizeColors>();
    if (stize == null) return _legacy(context);
    return _card(context, stize);
  }

  /// Stiže: a scheduled line as a filled transit-colour card, quieter than a
  /// live one — a clock time on the right, "Scheduled" in the caption, no live
  /// dot and no "min" unit.
  Widget _card(BuildContext context, StizeColors c) {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final on = c.onTransit;
    final fill = switch (cell.vehicleType) {
      VehicleType.bus => c.transitBus,
      VehicleType.tram => c.transitTram,
      VehicleType.trolleybus => c.transitTrolleybus,
    };
    final nearest = cell.etaMinutes.first;
    final followUps = cell.etaMinutes.skip(1).toList();
    final caption = StizeType.caption.copyWith(color: on.withValues(alpha: 0.8));

    return Opacity(
      opacity: 0.82,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(StizeRadius.radiusCard),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: StizeSpace.space4, vertical: StizeSpace.space3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(cell.line,
                        style: StizeType.section
                            .copyWith(fontWeight: FontWeight.w600, color: on)),
                    const SizedBox(height: StizeSpace.space1),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule,
                            size: 14, color: on.withValues(alpha: 0.8)),
                        const SizedBox(width: StizeSpace.space1),
                        Text(l10n.arrivalScheduled, style: caption),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: StizeSpace.space3),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Scheduled: a clock time, quieter (white 70%), never a count.
                  Text(
                    clockAt(localeName, nearest),
                    style: StizeType.date.copyWith(
                        fontWeight: FontWeight.w400,
                        color: on.withValues(alpha: 0.7)),
                  ),
                  if (followUps.isNotEmpty)
                    Text(
                      followUps.map((e) => clockAt(localeName, e)).join(' · '),
                      style: caption,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legacy(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final localeName = Localizations.localeOf(context).toString();
    final nearest = cell.etaMinutes.first;
    final followUps = cell.etaMinutes.skip(1).toList();

    return Opacity(
      opacity: _dimOpacity,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: vehicleColor(cell.vehicleType),
          child: vehicleGlyph(cell.vehicleType,
              size: 22, color: StizeColors.of(context).onTransit),
        ),
        title: Text(cell.line, style: theme.textTheme.titleMedium),
        subtitle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              l10n.arrivalScheduled,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Nearest scheduled, large — the "when's the next one" answer.
            Text(
              etaLabel(l10n, localeName, nearest),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            // The next two, small and muted — enough for the shape of the
            // schedule without turning the row into a full timetable. Far-off
            // times read as clock arrivals too (etaLabel).
            if (followUps.isNotEmpty)
              Text(
                followUps.map((e) => etaLabel(l10n, localeName, e)).join(' · '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
