import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:stigla/core/vehicle_map_mode.dart';
import 'package:stigla/domain/models/app_config.dart';
import 'package:stigla/l10n/app_localizations.dart';
import 'package:stigla/presentation/providers/providers.dart';
import 'package:stigla/presentation/screens/settings_screen.dart';

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

  /// The settings list is longer than the default 800×600 test window, and a
  /// ListView doesn't build what's off-screen — give it room so the section
  /// under Theme is actually laid out.
  Future<void> pumpSettings(WidgetTester tester, {required bool flagOn}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(flagOn: flagOn));
    await tester.pumpAndSettle();
  }

  testWidgets('flag OFF hides the transport-on-the-map setting', (tester) async {
    await pumpSettings(tester, flagOn: false);

    expect(find.text('Transport on the map'), findsNothing);
    expect(find.text('On demand'), findsNothing);
    expect(find.text('All transport'), findsNothing);
    // The rest of the screen is untouched.
    expect(find.text('Theme'), findsOneWidget);
  });

  testWidgets('flag ON shows it, defaulting to on-demand', (tester) async {
    await pumpSettings(tester, flagOn: true);

    expect(find.text('Transport on the map'), findsOneWidget);
    expect(find.text('Vehicles appear when you pick a stop or a vehicle.'), findsOneWidget);

    // Nothing stored yet ⇒ the default reads as selected, not "neither".
    RadioListTile<VehicleMapMode> radio(String label) =>
        tester.widget<RadioListTile<VehicleMapMode>>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(RadioListTile<VehicleMapMode>),
          ),
        );
    expect(radio('On demand').checked, isTrue);
    expect(radio('All transport').checked, isFalse);
  });

  testWidgets('picking "All transport" switches the map mode and persists', (tester) async {
    await pumpSettings(tester, flagOn: true);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(container.read(vehicleMapModeProvider), VehicleMapMode.onDemand);

    await tester.tap(find.text('All transport'));
    await tester.pumpAndSettle();

    // The mode the map watches flips right away — no restart.
    expect(container.read(vehicleMapModeProvider), VehicleMapMode.aquarium);
    // …and it survives a reload (stored, not just in memory).
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings_vehicle_map_mode'), 'aquarium');

    // Back to on-demand, on the fly.
    await tester.tap(find.text('On demand'));
    await tester.pumpAndSettle();
    expect(container.read(vehicleMapModeProvider), VehicleMapMode.onDemand);
  });
}
