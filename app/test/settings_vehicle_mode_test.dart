import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:stize/core/vehicle_map_mode.dart';
import 'package:stize/domain/models/app_config.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/providers/providers.dart';
import 'package:stize/presentation/screens/settings_screen.dart';

/// Settings with the `vehicles_on_demand` flag forced to [flagOn], reading the
/// real store on top of mocked prefs — the same path the app takes.
Widget _wrap({required bool flagOn}) => ProviderScope(
  overrides: [
    appConfigProvider.overrideWith(
      (ref) async => AppConfig(
        version: 'test',
        flags: {'vehicles_on_demand': flagOn},
      ),
    ),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const SettingsScreen(),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// The settings list can outgrow the default 800×600 test window, and a
  /// ListView doesn't build what's off-screen — give it room.
  Future<void> pumpSettings(WidgetTester tester, {required bool flagOn}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(flagOn: flagOn));
    await tester.pumpAndSettle();
  }

  testWidgets('languages are listed Serbian-first, after System', (tester) async {
    await pumpSettings(tester, flagOn: true);

    double topOf(String label) => tester.getTopLeft(find.text(label)).dy;

    expect(topOf('System'), lessThan(topOf('Srpski')));
    expect(topOf('Srpski'), lessThan(topOf('English')));
    expect(topOf('English'), lessThan(topOf('Русский')));
  });

  testWidgets('the vehicle mode is NOT a settings item — the map toggle owns it',
      (tester) async {
    // Even with the flag on, Settings offers only language + theme.
    await pumpSettings(tester, flagOn: true);

    expect(find.text('On demand'), findsNothing);
    expect(find.text('All transport'), findsNothing);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
  });

  /// A container wired like the app, with the flag forced and the config
  /// awaited — the mode resolves off `appConfigProvider`, so reading it before
  /// that future lands would just see the "config unreachable" default.
  Future<ProviderContainer> modeContainer({required bool flagOn}) async {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWith(
          (ref) async =>
              AppConfig(version: 'test', flags: {'vehicles_on_demand': flagOn}),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(appConfigProvider.future);
    await container.read(settingsControllerProvider.future);
    return container;
  }

  test('the mode persists and re-resolves without a restart', () async {
    final container = await modeContainer(flagOn: true);

    // Nothing stored yet ⇒ the flag-driven default.
    expect(container.read(vehicleMapModeProvider), VehicleMapMode.onDemand);

    await container
        .read(settingsControllerProvider.notifier)
        .setVehicleMapMode(VehicleMapMode.aquarium);

    // The mode the map watches flips right away…
    expect(container.read(vehicleMapModeProvider), VehicleMapMode.aquarium);
    // …and it survives a reload (stored, not just in memory).
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings_vehicle_map_mode'), 'aquarium');
  });

  test('a stored choice is read back on the next launch', () async {
    SharedPreferences.setMockInitialValues({
      'settings_vehicle_map_mode': 'aquarium',
    });
    final container = await modeContainer(flagOn: true);

    expect(container.read(vehicleMapModeProvider), VehicleMapMode.aquarium);
  });

  test('flag OFF forces the aquarium whatever is stored (killswitch)', () async {
    SharedPreferences.setMockInitialValues({
      'settings_vehicle_map_mode': 'onDemand',
    });
    final container = await modeContainer(flagOn: false);

    expect(container.read(vehicleMapModeProvider), VehicleMapMode.aquarium);
  });
}
