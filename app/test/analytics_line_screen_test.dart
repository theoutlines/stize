import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stigla/domain/models/line_analytics.dart';
import 'package:stigla/presentation/providers/providers.dart';
import 'package:stigla/presentation/screens/analytics_line_screen.dart';
import 'package:stigla/presentation/widgets/analytics/distribution_dots.dart';
import 'package:stigla/presentation/widgets/analytics/hourly_sparkline.dart';
import 'package:stigla/presentation/widgets/analytics/metric_chips.dart';
import 'package:stigla/presentation/widgets/analytics/time_heatmap.dart';

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
  grid: [
    for (var d = 1; d <= 5; d++)
      for (final h in const [8, 12, 17])
        AnalyticsCell(
          dow: d,
          hour: h,
          samples: 6 + d + h,
          arrivals: 3,
          meanHeadwaySecs: 300 + h * 10,
          meanSpeedStopsPerMin: 0.8,
        ),
  ],
  updatedAt: DateTime.now(),
);

final _empty = LineAnalytics(
  line: '79',
  totalSamples: 0,
  byHour: [for (var h = 0; h < 24; h++) _b(h)],
  byDow: [for (var d = 0; d < 7; d++) _b(d)],
  grid: const [],
  updatedAt: null,
);

Widget _wrap(LineAnalytics data) => ProviderScope(
  overrides: [
    lineAnalyticsProvider('79').overrideWith((ref) async => data),
  ],
  child: const MaterialApp(home: AnalyticsLineScreen(line: '79')),
);

void main() {
  testWidgets('renders each metric with its own visualisation type', (tester) async {
    // Tall viewport so the whole (lazy) ListView builds its cards.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap(_seeded()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Наблюдений: 120'), findsOneWidget);
    expect(find.byType(MetricChips), findsOneWidget);
    // Heatmaps (punctuality placeholder + real interval), sparkline, dot-plot.
    expect(find.byType(TimeHeatmap), findsWidgets);
    expect(find.byType(HourlySparkline), findsOneWidget);
    expect(find.byType(DistributionDots), findsOneWidget);
    expect(find.text('Реальный интервал · час × день'), findsOneWidget);
  });

  testWidgets('shows the humane empty state in the same visual language', (tester) async {
    await tester.pumpWidget(_wrap(_empty));
    await tester.pumpAndSettle();

    expect(find.text('Данных пока мало'), findsOneWidget);
    // Empty state keeps a pale placeholder grid but no data charts.
    expect(find.byType(TimeHeatmap), findsOneWidget);
    expect(find.byType(HourlySparkline), findsNothing);
    expect(find.byType(MetricChips), findsNothing);
  });
}
