import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/stize_text.dart';
import '../../core/design/stize_tokens.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'stize_filter_chips.dart';
import 'vehicle_icon.dart';

/// The Coverage level: what the heat on the map means, and which vehicle
/// types it shows. The map itself switches to coverage while this is open.
class CoveragePanel extends ConsumerWidget {
  const CoveragePanel({super.key});

  /// Tram, trolleybus, bus: the app's usual order, with the coverage `type`
  /// value each chip filters.
  static const _types = <(VehicleType, String)>[
    (VehicleType.tram, 'tram'),
    (VehicleType.trolleybus, 'trolleybus'),
    (VehicleType.bus, 'bus'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = StizeColors.of(context);
    final picked = ref.watch(coverageTypesProvider);
    void pick(String? type) => ref.read(coverageTypesProvider.notifier).state =
        toggleLineFilter(picked, type);
    String label(VehicleType t) => switch (t) {
      VehicleType.tram => l10n.vehicleTypeTram,
      VehicleType.trolleybus => l10n.vehicleTypeTrolleybus,
      VehicleType.bus => l10n.vehicleTypeBus,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: StizeSpace.space4),
          child: Row(
            spacing: StizeSpace.space2,
            children: [
              StizeTextChip(
                label: l10n.coverageFilterAll,
                selected: picked.isEmpty,
                onTap: () => pick(null),
              ),
              for (final (type, value) in _types)
                StizeTypeChip(
                  icon: vehicleIconFor(type),
                  label: label(type),
                  color: stizeChipColor(c, type),
                  selected: picked.contains(value),
                  onTap: () => pick(value),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            StizeSpace.space4,
            StizeSpace.space4,
            StizeSpace.space4,
            0,
          ),
          child: _DensityKey(
            rare: l10n.coverageLegendLow,
            busy: l10n.coverageLegendHigh,
          ),
        ),
      ],
    );
  }
}

/// "rarer … busier" under a bar that brightens the way the heat does: a
/// single route is a faint veil, a corridor many lines share glows.
class _DensityKey extends StatelessWidget {
  const _DensityKey({required this.rare, required this.busy});

  final String rare;
  final String busy;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    final note = StizeText.of(context).note;
    return Row(
      spacing: StizeSpace.space2,
      children: [
        Text(rare, style: note),
        Expanded(
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: LinearGradient(
                colors: [c.ink.withValues(alpha: 0.06), c.ink],
              ),
            ),
          ),
        ),
        Text(busy, style: note),
      ],
    );
  }
}
