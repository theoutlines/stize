import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stize/core/fleet_matcher.dart';
import 'package:stize/domain/models/vehicle_type.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/providers/providers.dart';
import 'package:stize/presentation/widgets/follow_view.dart';
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

Widget _wrap({
  required String? garageNo,
  List<FollowRouteStop> route = const [],
  bool between = false,
  int? stuckMinutes,
}) {
  final catalog = FleetCatalog.tryParse(_catalogJson)!;
  return ProviderScope(
    overrides: [fleetCatalogProvider.overrideWith((ref) async => catalog)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: VehicleView(
          line: '5',
          type: VehicleType.tram,
          garageNo: garageNo,
          route: route,
          vehicleBetween: between,
          stuckMinutes: stuckMinutes,
        ),
      ),
    ),
  );
}

const _route = [
  FollowRouteStop(name: 'Đeram pijaca', passed: true),
  FollowRouteStop(name: 'Lion', etaMinutes: 0, vehicleHere: true),
  FollowRouteStop(name: 'Pop Stojanova', etaMinutes: 1),
  FollowRouteStop(name: 'Batutova', etaMinutes: 3, yours: true),
];

void main() {
  testWidgets('the route lists the stops with times and your stop', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(garageNo: '81540', route: _route));
    await tester.pumpAndSettle();
    expect(find.text('Đeram pijaca'), findsOneWidget);
    expect(find.text('Lion'), findsOneWidget);
    expect(find.text('1 min'), findsOneWidget);
    expect(find.text('3 min'), findsOneWidget);
    expect(find.text('Your stop'), findsOneWidget);
    expect(find.textContaining('Stuck'), findsNothing);
  });

  testWidgets('a stuck vehicle says so on the route; later times turn ≈', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(garageNo: '81540', route: _route, stuckMinutes: 3),
    );
    await tester.pumpAndSettle();
    expect(find.text('Stuck · 3 min'), findsOneWidget);
    expect(find.text('≈ 1 min'), findsOneWidget);
    expect(find.text('≈ 3 min'), findsOneWidget);
  });

  testWidgets('a matched garage shows the vehicle card with its chips', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(garageNo: '81540'));
    await tester.pumpAndSettle();
    expect(find.text('Bozankaya'), findsOneWidget);
    expect(find.text('Articulated'), findsOneWidget);
    expect(find.textContaining('#81540'), findsOneWidget);
  });

  testWidgets('a junk placeholder id hides the vehicle card entirely', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(garageNo: 'P5'));
    await tester.pumpAndSettle();
    expect(find.text('Bozankaya'), findsNothing);
    expect(find.textContaining('#P5'), findsNothing);
  });
}
