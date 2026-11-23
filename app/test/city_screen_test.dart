import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stize/core/design/stize_theme.dart';
import 'package:stize/domain/models/city_analytics.dart';
import 'package:stize/domain/models/line_analytics.dart';
import 'package:stize/l10n/app_localizations.dart';
import 'package:stize/presentation/providers/providers.dart';
import 'package:stize/presentation/screens/city_screen.dart';

CityLine _line(
  String n,
  int arrivals,
  int? delay, {
  int dc = 40,
  int? evening,
}) => CityLine(
  line: n,
  arrivals: arrivals,
  delayCount: dc,
  meanDelaySecs: delay,
  headwayCount: 20,
  meanHeadwaySecs: 540,
  eveningHeadwayCount: evening == null ? 0 : 12,
  eveningMeanHeadwaySecs: evening,
);

CitySummary _summary({int arrivals = 5000}) => CitySummary(
  arrivals: arrivals,
  delayCount: 900,
  meanDelaySecs: 130,
  headwayCount: 400,
  meanHeadwaySecs: 540,
  grid: [
    for (var d = 0; d < 7; d++)
      for (var h = 6; h < 23; h++)
        CityCell(
          dow: d,
          hour: h,
          arrivals: 30,
          delayCount: 12,
          meanDelaySecs: (d == 2 && h == 17) ? 480 : 60 + h * 5,
          headwayCount: 10,
          meanHeadwaySecs: 600,
        ),
  ],
  lines: [
    _line('26', 1200, 20, evening: 900),
    _line('7L', 900, 140, evening: 1200),
    _line('74', 300, 520),
    _line('309', 25, null, dc: 0),
  ],
  aggregatedTo: DateTime(2026, 11, 23),
);

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: StizeTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );

void main() {
  setUp(() {});

  testWidgets('city: KPIs, the worst hour and best/worst lines in words', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(
        const CityScreen(),
        overrides: [
          citySummaryProvider.overrideWith((ref) async => _summary()),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('How Belgrade transport runs'), findsOneWidget);
    expect(find.text('2 min late'), findsOneWidget); // average delay KPI
    expect(
      find.textContaining('Worst: Tue at 17:00, about 8 min late'),
      findsOneWidget,
    );
    expect(
      find.text('26 is the most punctual line. 74 runs the latest.'),
      findsOneWidget,
    );
    // The thin line is drawn but not judged.
    expect(find.text('309'), findsOneWidget);
    expect(find.byType(DelayHeatmap), findsOneWidget);
  });

  testWidgets('city: too few arrivals shows the honest empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const CityScreen(),
        overrides: [
          citySummaryProvider.overrideWith(
            (ref) async => _summary(arrivals: 3),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not enough arrivals yet'), findsOneWidget);
    expect(find.byType(DelayHeatmap), findsNothing);
  });

  testWidgets('line page: a thin line gets the empty state with its count', (
    tester,
  ) async {
    const thin = LineAnalytics(
      line: '309',
      totalSamples: 12,
      byHour: [],
      byDow: [],
      grid: [
        AnalyticsCell(
          dow: 1,
          hour: 8,
          samples: 12,
          arrivals: 12,
          meanHeadwaySecs: null,
          meanSpeedStopsPerMin: null,
        ),
      ],
      updatedAt: null,
    );
    await tester.pumpWidget(
      _wrap(
        const CityLineScreen(line: '309'),
        overrides: [
          lineAnalyticsProvider('309').overrideWith((ref) async => thin),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('We have seen 12 arrivals'), findsOneWidget);
  });

  test('delay levels and wording', () {
    expect(delayLevel(30), 0);
    expect(delayLevel(200), 3);
    expect(delayLevel(500), 5);
  });
}
