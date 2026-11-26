import 'package:flutter/material.dart';

import 'vehicle_icon.dart';

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

/// Line-filter chip (owner pick C, 2026-11-24). Unpicked: the neutral
/// `fill-07` chip with the number in `ink-75`, like "All lines" at rest, so a
/// row of lines never reads as "all picked". Picked: the whole chip turns the
/// line's transit colour with a white number. 36 high, 20 radius, min 48 wide.
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
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? color : c.fill07,
        borderRadius: BorderRadius.circular(StizeRadius.radiusCard),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: StizeSize.chipH,
            constraints: const BoxConstraints(minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: StizeSpace.space3),
            // widthFactor 1: the chip is as wide as its number, never the row.
            child: Center(
              widthFactor: 1,
              child: Text(
                line,
                style: StizeType.control.copyWith(
                  fontSize: 16,
                  color: selected ? c.onTransit : c.ink75,
                ),
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

/// The next filter after a tap (owner, 2026-11-24). An empty set means
/// "All lines". From "All lines" a line tap picks only that line (nobody has to
/// untick the rest); after that taps add or remove lines; removing the last one
/// returns to "All lines". A tap on "All lines" ([line] null) clears the rest.
Set<String> toggleLineFilter(Set<String> current, String? line) {
  if (line == null) return const {};
  if (current.contains(line)) return {...current}..remove(line);
  return {...current, line};
}

/// The one line-filter row for both stop render paths (in-app
/// panel + /stop/:id): "All lines" + a chip per line with an arrival on the
/// board, one horizontally scrolling row starting at the cards' 16px edge.
class StizeLineFilterRow extends StatelessWidget {
  const StizeLineFilterRow({
    super.key,
    required this.allLabel,
    required this.lines,
    required this.typeByLine,
    required this.selected,
    required this.onSelect,
  });

  final String allLabel;

  /// Lines with an arrival on the board, in display order.
  final List<String> lines;
  final Map<String, VehicleType> typeByLine;

  /// The picked lines; empty = "All lines".
  final Set<String> selected;

  /// Called with the tapped line, or null for "All lines".
  final ValueChanged<String?> onSelect;

  /// Tram, trolleybus, bus: the order of the groups (owner, 2026-11-25).
  static const _typeOrder = [
    VehicleType.tram,
    VehicleType.trolleybus,
    VehicleType.bus,
  ];

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    // Grouped by vehicle type, each group led by its icon and set off by a
    // thin divider (variant F1). A stop with one type keeps a plain row.
    final groups = <VehicleType?, List<String>>{};
    for (final line in lines) {
      (groups[typeByLine[line]] ??= []).add(line);
    }
    final grouped = groups.length > 1;
    final order = [
      for (final t in _typeOrder)
        if (groups.containsKey(t)) t,
      if (groups.containsKey(null)) null,
    ];
    Widget chip(String line) => StizeLineChip(
      line: line,
      color: stizeChipColor(c, typeByLine[line]),
      selected: selected.contains(line),
      onTap: () => onSelect(line),
    );
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
            selected: selected.isEmpty,
            onTap: () => onSelect(null),
          ),
          if (!grouped)
            for (final line in lines) chip(line)
          else
            for (final t in order) ...[
              Container(width: 1, height: 24, color: c.fill16),
              if (t != null)
                Icon(
                  vehicleIconFor(t),
                  size: 18,
                  color: c.ink.withValues(alpha: 0.5),
                ),
              for (final line in groups[t]!) chip(line),
            ],
        ],
      ),
    );
  }
}
