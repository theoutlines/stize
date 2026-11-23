import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/widgets/guide/belgrade_guide.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: child),
);

void main() {
  test('hub detection: 300 m around the airport, not across town', () {
    expect(hubNear(44.81995, 20.29105), GuideHub.airport);
    expect(hubNear(44.8217, 20.29031), GuideHub.airport); // ~145 m
    expect(hubNear(44.8240, 20.29031), isNull); // ~400 m
  });

  test('night hours are 00:00 to 04:59', () {
    expect(isNightHour(DateTime(2026, 11, 23, 0, 30)), isTrue);
    expect(isNightHour(DateTime(2026, 11, 23, 4, 59)), isTrue);
    expect(isNightHour(DateTime(2026, 11, 23, 5, 0)), isFalse);
    expect(isNightHour(DateTime(2026, 11, 23, 23, 0)), isFalse);
  });

  testWidgets('daytime guide shows the Expo countdown and the hub rows', (
    tester,
  ) async {
    String? opened;
    await tester.pumpWidget(
      _host(
        GuideHome(
          now: DateTime(2026, 11, 23, 14),
          onOpenPage: (_) {},
          onOpenStop: (id, _) => opened = id,
        ),
      ),
    );
    expect(find.text('173'), findsOneWidget);
    expect(find.text('Night lines are running'), findsNothing);
    await tester.tap(find.text('From the airport'));
    expect(opened, GuideHub.airport.stopId);
  });

  testWidgets('at night the Right now card is about night lines', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        GuideHome(
          now: DateTime(2026, 11, 24, 1),
          onOpenPage: (_) {},
          onOpenStop: (_, _) {},
        ),
      ),
    );
    expect(find.text('Night lines are running'), findsOneWidget);
    expect(find.text('173'), findsNothing);
  });
}
