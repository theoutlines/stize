import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stize/domain/models/arrival.dart';
import 'package:stize/domain/models/vehicle_type.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/widgets/arrival_tile.dart';
import 'package:stize/presentation/widgets/stize_transit_card.dart';

Arrival _arrival({
  required String garageNo,
  LatLon? gps,
  bool scheduled = false,
  int eta = 6,
  int? stops = 3,
}) {
  return Arrival(
    line: '79',
    vehicleType: VehicleType.bus,
    etaMinutes: eta,
    stopsRemaining: stops,
    routeId: '79-0',
    gps: gps,
    garageNo: garageNo,
    scheduled: scheduled,
  );
}

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

StizeTransitCard _card(WidgetTester tester) =>
    tester.widget<StizeTransitCard>(find.byType(StizeTransitCard));

void main() {
  group('ArrivalTile — brightness == clickability', () {
    testWidgets('a live vehicle is a live, tappable card', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ArrivalTile(
            arrival: _arrival(
              garageNo: 'BG123',
              gps: const LatLon(44.8, 20.46),
            ),
            onTap: () {},
          ),
        ),
      );

      expect(_card(tester).live, isTrue);
      expect(_card(tester).onTap, isNotNull);
    });

    testWidgets(
      'a placeholder (terminus) card is held back, not tappable, says it starts here',
      (tester) async {
        // P2 = the schedule-derived placeholder class: valid ETA, no live position.
        await tester.pumpWidget(
          _wrap(
            ArrivalTile(
              arrival: _arrival(
                garageNo: 'P2',
                gps: const LatLon(44.8, 20.46),
                stops: 0,
              ),
              onTap: () {},
            ),
          ),
        );

        expect(_card(tester).live, isFalse);
        expect(_card(tester).onTap, isNull);
        expect(find.text('Starts here'), findsOneWidget);
      },
    );

    testWidgets(
      'a scheduled card is not tappable and carries no Scheduled word',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            ArrivalTile(
              arrival: _arrival(garageNo: 'BG9', scheduled: true, gps: null),
              onTap: () {},
            ),
          ),
        );

        expect(_card(tester).live, isFalse);
        expect(_card(tester).onTap, isNull);
        expect(find.text('Scheduled'), findsNothing);
      },
    );
  });
}
