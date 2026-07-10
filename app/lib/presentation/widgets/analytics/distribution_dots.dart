import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/line_analytics.dart';
import 'analytics_palette.dart';

/// A dot cloud of the interval distribution: one dot per (day, hour) slot with
/// data — x = hour, y = real interval (min), dot **size** = how many
/// observations back it, **colour** = reliability. Shows spread and where the
/// data is dense, rather than a single aggregate. fl_chart's ScatterChart fits
/// this directly.
class DistributionDots extends StatelessWidget {
  const DistributionDots({super.key, required this.grid});

  final List<AnalyticsCell> grid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cells = grid.where((c) => c.meanHeadwaySecs != null).toList();
    if (cells.isEmpty) {
      return SizedBox(
        height: 140,
        child: Center(child: Text('пока нет данных', style: theme.textTheme.bodySmall)),
      );
    }

    var maxSamples = 1, maxMin = 1.0;
    for (final c in cells) {
      if (c.samples > maxSamples) maxSamples = c.samples;
      final m = c.meanHeadwaySecs! / 60.0;
      if (m > maxMin) maxMin = m;
    }

    final spots = <ScatterSpot>[];
    for (final c in cells) {
      final minutes = c.meanHeadwaySecs! / 60.0;
      final radius = 3.0 + (c.samples / maxSamples) * 9.0;
      final t = (minutes / maxMin).clamp(0.0, 1.0); // longer interval → redder
      spots.add(
        ScatterSpot(
          c.hour.toDouble(),
          minutes,
          dotPainter: FlDotCirclePainter(
            radius: radius,
            color: AnalyticsPalette.reliability(t).withValues(alpha: 0.75),
          ),
        ),
      );
    }

    return SizedBox(
      height: 160,
      child: ScatterChart(
        ScatterChartData(
          minX: -0.5,
          maxX: 23.5,
          minY: 0,
          maxY: maxMin * 1.2,
          scatterTouchData: ScatterTouchData(enabled: true),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          scatterSpots: spots,
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (y, meta) =>
                    Text('${y.toInt()}м', style: theme.textTheme.labelSmall),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 6,
                reservedSize: 20,
                getTitlesWidget: (x, meta) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${x.toInt()}', style: theme.textTheme.labelSmall),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
