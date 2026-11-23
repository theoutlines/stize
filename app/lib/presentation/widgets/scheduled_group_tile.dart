import 'package:flutter/material.dart';

import 'stize_transit_card.dart';

import '../../core/arrival_grouping.dart';
import '../../core/design/stize_tokens.dart';
import '../../core/eta_format.dart';
import '../../l10n/app_localizations.dart';

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

  @override
  Widget build(BuildContext context) {
    // The Stiže card is live only when the design-system theme is on; OFF keeps
    // the previous dimmed ListTile (killswitch).
    return _card(context, StizeColors.of(context));
  }

  /// Stiže: a scheduled line as a neutral card with a transit-colour line
  /// badge, quieter than a live one — a clock time on the right, "Scheduled" in the caption, no live
  /// dot and no "min" unit.
  Widget _card(BuildContext context, StizeColors c) {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final caption = StizeTransitCard.captionStyle(c, scheduled: true);
    final followUps = cell.etaMinutes.skip(1).toList();
    return StizeTransitCard(
      type: cell.vehicleType,
      line: cell.line,
      caption: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 14, color: caption.color),
            const SizedBox(width: StizeSpace.space1),
            Text(l10n.arrivalScheduled, style: caption),
          ],
        ),
      ],
      etaMinutes: cell.etaMinutes.first,
      scheduled: true,
      etaFooter: followUps.isEmpty
          ? null
          : Text(
              followUps.map((e) => clockAt(localeName, e)).join(' · '),
              style: caption,
            ),
      live: false,
    );
  }
}
