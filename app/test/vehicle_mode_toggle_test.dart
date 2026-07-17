import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:stigla/core/vehicle_map_mode.dart';
import 'package:stigla/domain/models/app_config.dart';
import 'package:stigla/l10n/app_localizations.dart';
import 'package:stigla/presentation/providers/providers.dart';
import 'package:stigla/presentation/widgets/vehicle_mode_toggle.dart';

/// The toggle as the map hosts it: a Scaffold (so the toast has a messenger)
/// with the `vehicles_on_demand` flag forced to [flagOn].
Widget _wrap({required bool flagOn}) => ProviderScope(
  overrides: [
    appConfigProvider.overrideWith(
      (ref) async =>
          AppConfig(version: 'test', flags: {'vehicles_on_demand': flagOn}),
    ),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: VehicleModeToggle()),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(VehicleModeToggle)));

  testWidgets('flag OFF renders nothing at all (killswitch)', (tester) async {
    await tester.pumpWidget(_wrap(flagOn: false));
    await tester.pumpAndSettle();

    expect(find.byType(IconButton), findsNothing);
    // No leftover spacing either — the control stack must look untouched.
    expect(tester.getSize(find.byType(VehicleModeToggle)), Size.zero);
  });

  testWidgets('flag ON shows the button, plain in the default on-demand mode',
      (tester) async {
    await tester.pumpWidget(_wrap(flagOn: true));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.layers_outlined), findsOneWidget);
    expect(containerOf(tester).read(vehicleMapModeProvider),
        VehicleMapMode.onDemand);

    final theme = Theme.of(tester.element(find.byType(IconButton)));
    final material = tester.widget<Material>(
      find.ancestor(of: find.byType(IconButton), matching: find.byType(Material)).first,
    );
    expect(material.color, theme.colorScheme.surface,
        reason: 'the default mode leaves the button plain');
  });

  testWidgets('a tap flips the mode, names it in a toast, and persists it',
      (tester) async {
    await tester.pumpWidget(_wrap(flagOn: true));
    await tester.pumpAndSettle();
    final container = containerOf(tester);

    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    // Mode flipped — the map watches this and switches on the fly.
    expect(container.read(vehicleMapModeProvider), VehicleMapMode.aquarium);
    // The toast names the mode we landed in.
    expect(find.text('Transport on the map: All transport'), findsOneWidget);
    // …and the choice outlives a restart.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('settings_vehicle_map_mode'), 'aquarium');

    // Filled while the aquarium is on.
    final theme = Theme.of(tester.element(find.byType(IconButton)));
    final material = tester.widget<Material>(
      find.ancestor(of: find.byType(IconButton), matching: find.byType(Material)).first,
    );
    expect(material.color, theme.colorScheme.secondaryContainer);

    // Tapping back returns to on-demand.
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(container.read(vehicleMapModeProvider), VehicleMapMode.onDemand);
    expect(find.text('Transport on the map: On demand'), findsOneWidget);
  });

  testWidgets('a stored aquarium choice shows up as the active state',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings_vehicle_map_mode': 'aquarium',
    });
    await tester.pumpWidget(_wrap(flagOn: true));
    await tester.pumpAndSettle();

    expect(containerOf(tester).read(vehicleMapModeProvider),
        VehicleMapMode.aquarium);
  });
}
