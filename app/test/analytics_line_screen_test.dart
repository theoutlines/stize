import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stigla/domain/models/line_analytics.dart';
import 'package:stigla/presentation/providers/providers.dart';
import 'package:stigla/presentation/screens/analytics_line_screen.dart';

AnalyticsBucket _b(int key, {int samples = 0, double? headway, double? speed}) =>
    AnalyticsBucket(
      key: key,
      samples: samples,
      arrivals: samples ~/ 2,
      meanHeadwaySecs: headway,
      meanSpeedStopsPerMin: speed,
    );

LineAnalytics _seeded() => LineAnalytics(
  line: '79',
  totalSamples: 120,
  byHour: [
    for (var h = 0; h < 24; h++)
      _b(
        h,
        samples: (h >= 7 && h <= 20) ? 5 + h : 0,
        headway: (h >= 7 && h <= 20) ? 360 + h * 5 : null,
        speed: (h >= 7 && h <= 20) ? 0.8 : null,
      ),
  ],
  byDow: [for (var d = 0; d < 7; d++) _b(d, samples: 10 + d * 3)],
  updatedAt: DateTime.now(),
);

final _empty = LineAnalytics(
  line: '79',
  totalSamples: 0,
  byHour: [for (var h = 0; h < 24; h++) _b(h)],
  byDow: [for (var d = 0; d < 7; d++) _b(d)],
  updatedAt: null,
);

Widget _wrap(LineAnalytics data) => ProviderScope(
  overrides: [
    lineAnalyticsProvider('79').overrideWith((ref) async => data),
  ],
  child: const MaterialApp(home: AnalyticsLineScreen(line: '79')),
);

void main() {
  testWidgets('renders charts from real analytics data', (tester) async {
    await tester.pumpWidget(_wrap(_seeded()));
    await tester.pumpAndSettle();

    // The header reflects the data, and actual charts are drawn.
    expect(find.textContaining('Наблюдений: 120'), findsOneWidget);
    expect(find.byType(BarChart), findsWidgets);
    expect(find.text('Активность по часам'), findsOneWidget);
    expect(find.text('Реальный интервал по часам'), findsOneWidget);
  });

  testWidgets('shows the humane empty state when history is thin', (tester) async {
    await tester.pumpWidget(_wrap(_empty));
    await tester.pumpAndSettle();

    expect(find.text('Данных пока мало'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
  });
}
