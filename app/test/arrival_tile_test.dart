import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stigla/domain/models/arrival.dart';
import 'package:stigla/domain/models/vehicle_type.dart';
import 'package:stigla/l10n/app_localizations.dart';
import 'package:stigla/presentation/widgets/arrival_tile.dart';

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

/// The opacity applied to the leading line avatar — the dimming that signals
/// clickability at a glance.
double _leadingOpacity(WidgetTester tester) {
  final opacity = tester.widget<Opacity>(
    find
        .ancestor(of: find.byType(CircleAvatar), matching: find.byType(Opacity))
        .first,
  );
  return opacity.opacity;
}

void main() {
  group('ArrivalTile — brightness == clickability', () {
    testWidgets('a live vehicle is full brightness + shows a chevron', (tester) async {
      await tester.pumpWidget(_wrap(ArrivalTile(
        arrival: _arrival(garageNo: 'BG123', gps: const LatLon(44.8, 20.46)),
        onTap: () {},
      )));

      expect(_leadingOpacity(tester), 1.0);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('a placeholder (Expected) row is dimmed, no chevron, labelled Expected',
        (tester) async {
      // P2 = the schedule-derived placeholder class: valid ETA, no live position.
      await tester.pumpWidget(_wrap(ArrivalTile(
        arrival: _arrival(garageNo: 'P2', gps: const LatLon(44.8, 20.46), stops: 0),
        onTap: null,
      )));

      expect(_leadingOpacity(tester), lessThan(1.0));
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.text('Expected'), findsOneWidget);
    });

    testWidgets('a scheduled row is dimmed, no chevron, labelled By schedule',
        (tester) async {
      await tester.pumpWidget(_wrap(ArrivalTile(
        arrival: _arrival(garageNo: 'BG9', scheduled: true, gps: null),
        onTap: null,
      )));

      expect(_leadingOpacity(tester), lessThan(1.0));
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.text('Scheduled'), findsOneWidget);
    });
  });
}
