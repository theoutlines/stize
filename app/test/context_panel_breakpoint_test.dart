import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:stigla/core/map_support.dart';
import 'package:stigla/data/location/location_service.dart';
import 'package:stigla/domain/models/app_config.dart';
import 'package:stigla/domain/models/stop.dart';
import 'package:stigla/l10n/app_localizations.dart';
import 'package:stigla/presentation/providers/providers.dart';
import 'package:stigla/presentation/screens/home_map_screen.dart';
import 'package:stigla/presentation/widgets/context_shell.dart';
import 'package:stigla/presentation/widgets/nearby_sheet.dart';

/// Location permanently denied → the map never starts a stream (keeps the test
/// hermetic; the nearby view just shows its "enable location" state).
class _DeniedLocation extends LocationService {
  @override
  Future<bool> isPermissionGranted() async => false;
  @override
  Future<Position?> lastKnownIfGranted() async => null;
}

Widget _host({required Size size}) {
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWith(
        (ref) async => const AppConfig(version: 'test', flags: {
          'context_panel': true,
          'nearby_list': true,
          'vehicles_on_demand': true,
        }),
      ),
      locationServiceProvider.overrideWithValue(_DeniedLocation()),
      favoriteStopLocationsProvider.overrideWith((ref) async => const <Stop>[]),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: const HomeMapScreen(),
      ),
    ),
  );
}

void main() {
  // The screen builds a MapLibreMap, which throws under `flutter test`; the flag
  // makes map widgets render placeholders instead.
  setUp(() => kMapRenderingEnabled = false);
  tearDown(() => kMapRenderingEnabled = true);

  testWidgets('desktop (≥840) shows the left panel, not the bottom sheet',
      (tester) async {
    await tester.pumpWidget(_host(size: const Size(1200, 800)));
    await tester.pump(); // let appConfig resolve
    await tester.pump();
    expect(find.byType(ContextPanel), findsOneWidget);
    expect(find.byType(NearbySheet), findsNothing);
  });

  testWidgets(
      'mobile (<840) keeps the LEGACY sheets, not the panel (owner R1 #1: '
      'panel is desktop-only, mobile untouched)', (tester) async {
    await tester.pumpWidget(_host(size: const Size(400, 800)));
    await tester.pump();
    await tester.pump();
    // The panel never appears on mobile; the legacy Nearby sheet does.
    expect(find.byType(ContextPanel), findsNothing);
    expect(find.byType(NearbySheet), findsOneWidget);
  });

  testWidgets(
      'resizing across 840 swaps only the overlay but keeps ONE map alive',
      (tester) async {
    await tester.pumpWidget(_host(size: const Size(1200, 800)));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ContextPanel), findsOneWidget);
    expect(find.byType(NearbySheet), findsNothing);
    final stateBefore = tester.state(find.byType(HomeMapScreen));

    // Cross the breakpoint to mobile.
    await tester.pumpWidget(_host(size: const Size(400, 800)));
    await tester.pump();
    await tester.pump();

    // Overlay swapped to the legacy mobile UI…
    expect(find.byType(ContextPanel), findsNothing);
    expect(find.byType(NearbySheet), findsOneWidget);
    // …and it's the SAME HomeMapScreen State (the map was never rebuilt from
    // scratch — no IndexedStack/render-cycle recreation).
    expect(tester.state(find.byType(HomeMapScreen)), stateBefore);
  });
}
