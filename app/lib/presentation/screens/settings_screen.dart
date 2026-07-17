import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/vehicle_map_mode.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';

const _localeOptions = <String?>[null, 'en', 'ru', 'sr'];

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settingsAsync = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    // The `vehicles_on_demand` killswitch: with the flag off the choice isn't
    // offered at all and the map stays the aquarium (resolveVehicleMapMode).
    final vehicleModeOffered = ref.watch(vehiclesOnDemandEnabledProvider);
    final vehicleMode = ref.watch(vehicleMapModeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (err, st) => Center(child: Text(err.toString())),
        data: (settings) => ListView(
          children: [
            ListTile(title: Text(l10n.settingsLanguage)),
            for (final code in _localeOptions)
              RadioListTile<String?>.adaptive(
                title: Text(_localeLabel(code)),
                value: code,
                groupValue: settings.localeCode,
                onChanged: (value) => controller.setLocaleCode(value),
              ),
            const Divider(),
            ListTile(title: Text(l10n.settingsTheme)),
            RadioListTile<ThemeMode>.adaptive(
              title: Text(l10n.settingsThemeSystem),
              value: ThemeMode.system,
              groupValue: settings.themeMode,
              onChanged: (value) => controller.setThemeMode(value!),
            ),
            RadioListTile<ThemeMode>.adaptive(
              title: Text(l10n.settingsThemeLight),
              value: ThemeMode.light,
              groupValue: settings.themeMode,
              onChanged: (value) => controller.setThemeMode(value!),
            ),
            RadioListTile<ThemeMode>.adaptive(
              title: Text(l10n.settingsThemeDark),
              value: ThemeMode.dark,
              groupValue: settings.themeMode,
              onChanged: (value) => controller.setThemeMode(value!),
            ),
            if (vehicleModeOffered) ...[
              const Divider(),
              ListTile(title: Text(l10n.settingsVehicles)),
              RadioListTile<VehicleMapMode>.adaptive(
                title: Text(l10n.settingsVehiclesOnDemand),
                subtitle: Text(l10n.settingsVehiclesOnDemandHint),
                value: VehicleMapMode.onDemand,
                // The resolved mode, not the raw stored choice: until the user
                // picks, the default must show as selected rather than neither.
                groupValue: vehicleMode,
                onChanged: (value) => controller.setVehicleMapMode(value),
              ),
              RadioListTile<VehicleMapMode>.adaptive(
                title: Text(l10n.settingsVehiclesAll),
                value: VehicleMapMode.aquarium,
                groupValue: vehicleMode,
                onChanged: (value) => controller.setVehicleMapMode(value),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _localeLabel(String? code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'ru':
        return 'Русский';
      case 'sr':
        return 'Srpski';
      default:
        return 'System';
    }
  }
}
