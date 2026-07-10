import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/line_analytics.dart';

/// One line on the sparkline: a label, a colour and the hourly metric to plot.
class HourlySeries {
  const HourlySeries({
    required this.label,
    required this.color,
    required this.byHour,
    required this.valueOf,
  });

  final String label;
  final Color color;
  final List<AnalyticsBucket> byHour;
  final double? Function(AnalyticsBucket) valueOf;
}

/// Smooth line chart over the 24 hours — for trends and, with two series,
/// comparing lines on the same axis. fl_chart is purpose-built for this
/// (curves, touch, legend) so we use it directly here.
class HourlySparkline extends StatelessWidget {
  const HourlySparkline({super.key, required this.series});

  final List<HourlySeries> series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bars = <LineChartBarData>[];
    double maxY = 0;
    for (final s in series) {
      final spots = <FlSpot>[];
      for (final b in s.byHour) {
        final v = s.valueOf(b);
        if (v != null && v > 0) {
          spots.add(FlSpot(b.key.toDouble(), v));
          if (v > maxY) maxY = v;
        }
      }
      bars.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          preventCurveOverShooting: true,
          color: s.color,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: series.length == 1,
            color: s.color.withValues(alpha: 0.12),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 140,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: 23,
              minY: 0,
              maxY: maxY <= 0 ? 1 : maxY * 1.2,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: true),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
              lineBarsData: bars,
            ),
          ),
        ),
        if (series.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: [
              for (final s in series)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 12, height: 3, color: s.color),
                    const SizedBox(width: 6),
                    Text(s.label, style: theme.textTheme.labelMedium),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}
