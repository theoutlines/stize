import 'package:flutter/material.dart';

import '../../core/design/stize_tokens.dart';
import '../../domain/models/arrival.dart';
import '../../domain/models/vehicle_type.dart';

/// The Stiže transit colour for a line-filter chip, so a chip reads the same
/// colour as that line's card and map marker. A line with no known type (no
/// live arrival right now) falls back to the neutral mixed colour.
Color stizeChipColor(StizeColors stize, VehicleType? type) => switch (type) {
  VehicleType.bus => stize.transitBus,
  VehicleType.tram => stize.transitTram,
  VehicleType.trolleybus => stize.transitTrolleybus,
  null => stize.transitMixed,
};

/// A line → its vehicle type, taken from the board's own arrivals (so chip
/// colour == card colour).
Map<String, VehicleType> stizeTypeByLine(Iterable<Arrival> arrivals) {
  final m = <String, VehicleType>{};
  for (final a in arrivals) {
    m.putIfAbsent(a.line, () => a.vehicleType);
  }
  return m;
}

/// The ETA (minutes) of the next arrival of [current]'s line after it — the
/// "next in N min" caption on a card. Matches by line (the grouped view already
/// folds direction), taking the smallest ETA strictly greater than this one.
int? stizeNextEtaForLine(List<Arrival> all, Arrival current) {
  int? best;
  for (final a in all) {
    if (a.line != current.line) continue;
    if (a.etaMinutes <= current.etaMinutes) continue;
    if (best == null || a.etaMinutes < best) best = a.etaMinutes;
  }
  return best;
}

/// Line-filter chip filled with the line's transit colour (white number), 36
/// high / 20 radius, min-width 48. A picked chip keeps its fill and adds an
/// ink ring.
class StizeLineChip extends StatelessWidget {
  const StizeLineChip({
    super.key,
    required this.line,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String line;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(StizeRadius.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: StizeSize.chipH,
          constraints: const BoxConstraints(minWidth: 48),
          padding: const EdgeInsets.symmetric(horizontal: StizeSpace.space3),
          decoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(StizeRadius.radiusCard),
                  border: Border.all(color: c.ink, width: 2),
                )
              : null,
          // widthFactor 1: the chip is as wide as its number, never the row.
          child: Center(
            widthFactor: 1,
            child: Text(
              line,
              style: StizeType.control.copyWith(
                fontSize: 16,
                color: c.onTransit,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Neutral text chip ("All lines"): fill-07 at rest, ink when picked.
class StizeTextChip extends StatelessWidget {
  const StizeTextChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    return Material(
      color: selected ? c.ink : c.fill07,
      borderRadius: BorderRadius.circular(StizeRadius.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: StizeSize.chipH,
          padding: const EdgeInsets.symmetric(horizontal: StizeSpace.space4),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: StizeType.control.copyWith(
                fontSize: 16,
                color: selected ? c.onInk : c.ink75,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The one line-filter row for both stop render paths (in-app
/// panel + /stop/:id): "All lines" + a transit-colour chip per line, one
/// horizontally scrolling row starting at the cards' 16px edge. Lines with no
/// arrival right now are shown faded and inert.
class StizeLineFilterRow extends StatelessWidget {
  const StizeLineFilterRow({
    super.key,
    required this.allLabel,
    required this.allLines,
    required this.arrivingLines,
    required this.typeByLine,
    required this.selected,
    required this.onSelect,
  });

  final String allLabel;
  final List<String> allLines;
  final Set<String> arrivingLines;
  final Map<String, VehicleType> typeByLine;

  /// The picked line, or null for "All lines".
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: StizeSpace.space4,
        vertical: StizeSpace.space1,
      ),
      child: Row(
        spacing: StizeSpace.space2,
        children: [
          StizeTextChip(
            label: allLabel,
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final line in allLines)
            if (arrivingLines.contains(line))
              StizeLineChip(
                line: line,
                color: stizeChipColor(c, typeByLine[line]),
                selected: selected == line,
                onTap: () => onSelect(line),
              )
            else
              Opacity(
                opacity: 0.4,
                child: StizeLineChip(
                  line: line,
                  color: stizeChipColor(c, typeByLine[line]),
                  selected: false,
                  onTap: null,
                ),
              ),
        ],
      ),
    );
  }
}
