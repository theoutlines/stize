import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stize/core/fleet_matcher.dart';
import 'package:stize/domain/models/vehicle_type.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/providers/providers.dart';
import 'package:stize/presentation/widgets/vehicle_view.dart';

// A garage in [81531,81560] resolves to the Bozankaya class (AC / low-floor /
// comfort 5); anything else is unknown; a P1..P999 id is a junk placeholder.
const _catalogJson = '''
{
 "classes": [
  {"id":"bozankaya","type":"tram","ranges":[[81531,81560]],"model":"Bozankaya",
   "ac":true,"low_floor":true,"usb":true,"articulated":true,
   "powertrain":"tram","comfort_score":5,"years_built":[2024,2026],
   "confidence":{"ranges":"verified"}}
 ],
 "models_catalog": {},
 "vehicles": {}
}
''';

Widget _wrap({required String? garageNo}) {
  final catalog = FleetCatalog.tryParse(_catalogJson)!;
  return ProviderScope(
    overrides: [
      fleetCatalogProvider.overrideWith((ref) async => catalog),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: VehicleView(
          line: '5',
          type: VehicleType.tram,
          origin: 'Batutova',
          destination: 'Zeleni venac',
          garageNo: garageNo,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('direction + status render', (tester) async {
    await tester.pumpWidget(_wrap(garageNo: '81540'));
    await tester.pumpAndSettle();
    expect(find.text('Batutova → Zeleni venac'), findsOneWidget);
    expect(find.text('On the move'), findsOneWidget);
  });

  testWidgets('a matched garage shows the About card + model + CTA (decision #7)',
      (tester) async {
    await tester.pumpWidget(_wrap(garageNo: '81540'));
    await tester.pumpAndSettle();
    expect(find.text('About the vehicle'), findsOneWidget);
    expect(find.text('Bozankaya'), findsOneWidget);
    expect(find.textContaining('View model details'), findsOneWidget);
  });

  testWidgets('a junk placeholder id hides the About card entirely (decision #7)',
      (tester) async {
    await tester.pumpWidget(_wrap(garageNo: 'P5'));
    await tester.pumpAndSettle();
    // No card, no CTA — the placeholder number is never surfaced.
    expect(find.text('About the vehicle'), findsNothing);
    expect(find.textContaining('View model details'), findsNothing);
  });

  testWidgets('a real-but-unmatched garage still shows (muted), no CTA',
      (tester) async {
    // 70260 is a plausible number outside every class range → unknown.
    await tester.pumpWidget(_wrap(garageNo: '70260'));
    await tester.pumpAndSettle();
    expect(find.text('About the vehicle'), findsOneWidget);
    // The muted garage number is shown; no "view model" CTA (nothing to open).
    expect(find.textContaining('View model details'), findsNothing);
  });

  testWidgets(
      'a line with no route geometry shows the honest note, not a route list '
      '(owner R4 #2)', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [fleetCatalogProvider.overrideWith((ref) async => null)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: VehicleView(
            line: 'Ada 4',
            type: VehicleType.bus,
            garageNo: null,
            routeUnavailable: true,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Route unavailable for this line'), findsOneWidget);
    expect(find.text('Rest of the route'), findsNothing);
  });
}
