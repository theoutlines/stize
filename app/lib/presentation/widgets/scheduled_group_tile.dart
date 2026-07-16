import 'package:flutter/material.dart';

import '../../core/arrival_grouping.dart';
import '../../core/eta_format.dart';
import '../../core/map_support.dart';
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
          child: vehicleGlyph(cell.vehicleType, size: 22, color: Colors.white),
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
