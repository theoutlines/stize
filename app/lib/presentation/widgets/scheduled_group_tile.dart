import 'package:flutter/material.dart';

import 'stize_transit_card.dart';

import '../../core/arrival_grouping.dart';
import '../../core/design/stize_icons.dart';
import '../../core/design/stize_tokens.dart';
import '../../core/eta_format.dart';

/// One line×direction of the timetable section: the nearest clock time large,
/// up to two follow-ups small under it. A neutral card with a coloured line
/// plate: no "Scheduled" word and no clock icon on the card, the section header
/// above already says these come from the timetable.
class ScheduledGroupTile extends StatelessWidget {
  const ScheduledGroupTile({super.key, required this.cell, this.destination});

  final ScheduledGroupCell cell;

  /// The direction's destination; null hides the row.
  final String? destination;

  @override
  Widget build(BuildContext context) {
    final localeName = Localizations.localeOf(context).toString();
    final followUps = cell.etaMinutes.skip(1).toList();
    return StizeTransitCard(
      type: cell.vehicleType,
      line: cell.line,
      destination: destination,
      etaMinutes: cell.etaMinutes.first,
      scheduled: true,
      followUps: followUps.isEmpty
          ? null
          : followUps.map((e) => clockAt(localeName, e)).join(' · '),
      live: false,
    );
  }
}

/// The header that opens the timetable section of a stop board: one clock icon
/// and "By timetable", quiet, so the section reads as a different kind of
/// information without repeating a clock on every card.
class TimetableHeader extends StatelessWidget {
  const TimetableHeader({
    super.key,
    required this.label,
    this.icon = StizeIcons.clock,
  });

  final String label;

  /// The clock for "By timetable"; the offline mark when live is down and the
  /// timetable stands in for it.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    final color = c.ink.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        StizeSpace.space4,
        StizeSpace.space5,
        StizeSpace.space4,
        StizeSpace.space2,
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: StizeType.caption.copyWith(color: color)),
        ],
      ),
    );
  }
}
