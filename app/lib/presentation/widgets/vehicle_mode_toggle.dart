import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/vehicle_map_mode.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';

/// The map's quick toggle between on-demand vehicles and the background
/// "aquarium" — the single control for the mode (there is deliberately no
/// Settings item). Renders nothing while the `vehicles_on_demand` flag is off:
/// that's the killswitch, and the map is then the aquarium regardless.
///
/// The choice is persisted, so it survives a restart, and the map switches on
/// the fly — no restart, no reload.
class VehicleModeToggle extends ConsumerWidget {
  const VehicleModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(vehiclesOnDemandEnabledProvider)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mode = ref.watch(vehicleMapModeProvider);
    // Filled = the aquarium is on. The default (on-demand) leaves the button
    // plain, so a highlighted button always means "you asked for more than the
    // default", the way a map's layers button reads.
    final aquarium = mode == VehicleMapMode.aquarium;

    // The gap to the button below is ours, so that hiding this widget hides the
    // spacing with it and the control stack reads exactly as it does today.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PointerInterceptor(
        child: Material(
          color: aquarium
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.surface,
          elevation: 3,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: IconButton(
            icon: const Icon(Icons.layers_outlined),
            color: aquarium ? theme.colorScheme.onSecondaryContainer : null,
            tooltip: l10n.vehicleModeTooltip,
            onPressed: () => _flip(context, ref, mode, l10n),
          ),
        ),
      ),
    );
  }

  void _flip(
    BuildContext context,
    WidgetRef ref,
    VehicleMapMode mode,
    AppLocalizations l10n,
  ) {
    final next = mode == VehicleMapMode.onDemand
        ? VehicleMapMode.aquarium
        : VehicleMapMode.onDemand;
    ref.read(settingsControllerProvider.notifier).setVehicleMapMode(next);
    // Name the mode we just switched to — the button state alone is easy to
    // misread, and the map's own change (vehicles appearing/vanishing) can be
    // off-screen behind a sheet.
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.vehicleModeSwitched(vehicleModeLabel(next, l10n))),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }
}

String vehicleModeLabel(VehicleMapMode mode, AppLocalizations l10n) =>
    switch (mode) {
      VehicleMapMode.onDemand => l10n.vehicleModeOnDemand,
      VehicleMapMode.aquarium => l10n.vehicleModeAll,
    };
