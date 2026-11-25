import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stize/core/design/stize_theme.dart';
import 'package:stize/core/design/stize_tokens.dart';
import 'package:stize/domain/models/arrival.dart';
import 'package:stize/domain/models/vehicle_type.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/widgets/arrival_tile.dart';

/// The Stiže arrival card is drawn only when the design-system theme carries the
/// StizeColors extension (the `ds_stize` flag ON); these pump the card with that
/// theme and assert the owner-approved card look.
Arrival _arrival({
  VehicleType type = VehicleType.bus,
  int eta = 6,
  int? stops = 3,
  bool scheduled = false,
  LatLon? gps = const LatLon(44.8, 20.46),
  String garageNo = 'BG123',
}) => Arrival(
  line: '79',
  vehicleType: type,
  etaMinutes: eta,
  stopsRemaining: stops,
  routeId: '79-0',
  gps: gps,
  garageNo: garageNo,
  scheduled: scheduled,
);

Widget _wrap(Widget child) => MaterialApp(
  theme: StizeTheme.dark(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: child),
);

Color _cardFill(WidgetTester tester) {
  final material = tester.widget<Material>(
    find.ancestor(of: find.text('79'), matching: find.byType(Material)).first,
  );
  return material.color!;
}

void main() {
  testWidgets('a live card is filled with the transit colour, white number', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(ArrivalTile(arrival: _arrival())));
    expect(_cardFill(tester), StizeColors.dark.transitBus);
    expect(find.text('79'), findsOneWidget);
  });

  testWidgets('ETA shows the number with a min unit; destination + next trip', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ArrivalTile(
          arrival: _arrival(eta: 6),
          destination: 'Vukov spomenik',
          laterEtaMinutes: const [9, 21, 34],
          stuck: false,
        ),
      ),
    );
    expect(find.text('6'), findsOneWidget);
    expect(find.text('min'), findsOneWidget);
    expect(find.text('Vukov spomenik'), findsOneWidget);
    // The later vehicles of this direction, up to three (owner, 2026-11-25).
    expect(find.text('next 9 · 21 · 34 min'), findsOneWidget);
    expect(find.text('3 stops away'), findsOneWidget);
    expect(find.text('≈'), findsNothing);
  });

  testWidgets('a due vehicle reads "now", not 0', (tester) async {
    await tester.pumpWidget(
      _wrap(ArrivalTile(arrival: _arrival(eta: 0, stops: 0))),
    );
    expect(find.text('now'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('a timetable row shows a clock time, no Scheduled word', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        ArrivalTile(arrival: _arrival(scheduled: true, gps: null, eta: 20)),
      ),
    );
    // The section header says "By timetable"; the card doesn't repeat it.
    expect(find.text('Scheduled'), findsNothing);
    // No "min" unit on a scheduled row — it shows a clock time instead.
    expect(find.text('min'), findsNothing);
  });

  testWidgets('a vehicle waiting at the terminus says it starts here', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(ArrivalTile(arrival: _arrival(garageNo: 'P3', eta: 4))),
    );
    expect(find.text('Starts here'), findsOneWidget);
  });

  testWidgets('a vehicle that stopped moving shows an approximate time', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(ArrivalTile(arrival: _arrival(eta: 8), stuck: true)),
    );
    expect(find.text('≈'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
  });

  testWidgets('the trolleybus card is the darkened orange', (tester) async {
    await tester.pumpWidget(
      _wrap(ArrivalTile(arrival: _arrival(type: VehicleType.trolleybus))),
    );
    expect(_cardFill(tester), StizeColors.dark.transitTrolleybus);
  });
}
