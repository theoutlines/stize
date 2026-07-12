import 'package:flutter/material.dart';

import '../../core/fleet_matcher.dart';
import '../../l10n/app_localizations.dart';

/// Shared Fleet-ID visual vocabulary (task B2/B3). Small, glanceable badges the
/// arrivals list and the model card both draw from, so a "❄️" or the eco green
/// reads the same in both places.

/// Green for zero-emission (electric / trolley / tram), amber for hybrids.
const _ecoColor = Color(0xFF1E7A46);
const _hybridColor = Color(0xFFB25A00);
const _acColor = Color(0xFF1B67C4);

/// Vehicle age in whole years from the middle of the build range, or null when
/// build years are unknown. Anchored to the current calendar year.
int? fleetAgeYears(FleetVehicle fleet, {DateTime? now}) {
  final mid = fleet.midYear;
  if (mid == null) return null;
  final year = (now ?? DateTime.now()).year;
  final age = year - mid;
  return age < 0 ? 0 : age;
}

/// Compact one-line strip shown next to the ETA in the arrivals list.
///
/// - model/class-hit → amenity icons + age chip, tappable to open the card;
/// - UNKNOWN → only the muted garage number (nothing invented);
/// - UNKNOWN_JUNK → nothing at all (the placeholder number is never shown).
class FleetBadgeStrip extends StatelessWidget {
  const FleetBadgeStrip({
    super.key,
    required this.fleet,
    this.garageNo,
    this.onTap,
  });

  final FleetVehicle fleet;
  final String? garageNo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    if (!fleet.hasInfo) {
      // Junk placeholder ids are hidden entirely; a real-but-unmatched number
      // is shown muted so the passenger still has *something* to identify it by.
      if (fleet.kind == FleetMatchKind.unknownJunk) return const SizedBox.shrink();
      final n = garageNo;
      if (n == null || n.trim().isEmpty) return const SizedBox.shrink();
      return Text(
        l10n.fleetVehicleNumber(n),
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
      );
    }

    final approx = fleet.approximate;
    final badges = <Widget>[];

    // Eco / powertrain.
    if (fleet.powertrain.isElectric) {
      badges.add(_icon(Icons.eco, _ecoColor, assumed: false));
    } else if (fleet.powertrain == Powertrain.hybrid) {
      badges.add(_icon(Icons.eco, _hybridColor, assumed: approx));
    }

    // Air conditioning (positive only — "no AC" is left for the card).
    if (fleet.ac == true) {
      badges.add(_icon(Icons.ac_unit, _acColor, assumed: approx || fleet.isAssumed('ac')));
    }

    // Low floor / accessibility.
    if (fleet.lowFloor == true) {
      badges.add(_icon(Icons.accessible, theme.colorScheme.onSurfaceVariant,
          assumed: approx || fleet.isAssumed('low_floor')));
    }

    final age = fleetAgeYears(fleet);
    if (age != null) {
      badges.add(_ageChip(context, age, assumed: approx || fleet.isAssumed('years_built')));
    }

    if (badges.isEmpty) return const SizedBox.shrink();

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (approx)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Text('~',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ),
        for (var i = 0; i < badges.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          badges[i],
        ],
      ],
    );

    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: row,
      ),
    );
  }

  Widget _icon(IconData icon, Color color, {required bool assumed}) {
    return Icon(icon, size: 15, color: assumed ? color.withValues(alpha: 0.5) : color);
  }

  Widget _ageChip(BuildContext context, int age, {required bool assumed}) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final color = theme.colorScheme.outline;
    return Text(
      l10n.fleetAgeYears(age),
      style: theme.textTheme.bodySmall?.copyWith(
        color: assumed ? color.withValues(alpha: 0.7) : color,
        fontFeatures: const [],
      ),
    );
  }
}
