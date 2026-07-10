import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/line_analytics.dart';
import '../providers/providers.dart';

/// Draft analytics screen for a single line: real-history charts (activity,
/// interval, speed) built from accumulated observations. Visual is intentionally
/// rough — the point is that the charts render from real data. Gated behind the
/// remote `analytics_show` flag (see the drawer entry / router).
class AnalyticsLineScreen extends ConsumerWidget {
  const AnalyticsLineScreen({super.key, required this.line});

  final String line;

  static const _dowLabels = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lineAnalyticsProvider(line));
    return Scaffold(
      appBar: AppBar(title: Text('Аналитика · линия $line')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Message(
          icon: Icons.cloud_off,
          title: 'Не удалось загрузить',
          body: 'Попробуй позже.',
        ),
        data: (a) => a.hasData
            ? _charts(context, a)
            : const _Message(
                icon: Icons.hourglass_bottom,
                title: 'Данных пока мало',
                body:
                    'Мы только начали копить историю по этой линии. '
                    'Загляни позже — графики наполнятся со временем.',
              ),
      ),
    );
  }

  Widget _charts(BuildContext context, LineAnalytics a) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Наблюдений: ${a.totalSamples}'
          '${a.updatedAt != null ? ' · обновлено ${_ago(a.updatedAt!)}' : ''}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        _ChartCard(
          title: 'Активность по часам',
          subtitle: 'число наблюдений',
          child: _HourlyBars(
            buckets: a.byHour,
            valueOf: (b) => b.samples.toDouble(),
            color: theme.colorScheme.primary,
          ),
        ),
        _ChartCard(
          title: 'Реальный интервал по часам',
          subtitle: 'минуты между машинами (чем ниже — тем чаще)',
          child: _HourlyBars(
            buckets: a.byHour,
            valueOf: (b) =>
                b.meanHeadwaySecs == null ? null : b.meanHeadwaySecs! / 60.0,
            color: Colors.teal,
          ),
        ),
        _ChartCard(
          title: 'Скорость по часам',
          subtitle: 'остановок в минуту (динамика хода)',
          child: _HourlyBars(
            buckets: a.byHour,
            valueOf: (b) => b.meanSpeedStopsPerMin,
            color: Colors.deepOrange,
          ),
        ),
        _ChartCard(
          title: 'Активность по дням недели',
          subtitle: 'число наблюдений',
          child: _HourlyBars(
            buckets: a.byDow,
            valueOf: (b) => b.samples.toDouble(),
            color: theme.colorScheme.tertiary,
            labelOf: (i) => _dowLabels[i % 7],
            maxBars: 7,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Пунктуальность'),
            subtitle: const Text(
              'Скоро: опоздание считается относительно расписания GTFS — '
              'приближение, и только для остановок, где расписание есть.',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Черновой экран. Метрики строятся на реальных накопленных данных; '
          'чем дольше копится история, тем точнее картина.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes} мин назад';
    if (d.inHours < 24) return '${d.inHours} ч назад';
    return '${d.inDays} дн назад';
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            Text(subtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            SizedBox(height: 160, child: child),
          ],
        ),
      ),
    );
  }
}

/// A bar per bucket (24 hours by default, or 7 days). Null metric values render
/// as gaps (no data), not zeros.
class _HourlyBars extends StatelessWidget {
  const _HourlyBars({
    required this.buckets,
    required this.valueOf,
    required this.color,
    this.labelOf,
    this.maxBars = 24,
  });

  final List<AnalyticsBucket> buckets;
  final double? Function(AnalyticsBucket) valueOf;
  final Color color;
  final String Function(int index)? labelOf;
  final int maxBars;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = <int, double>{};
    for (final b in buckets) {
      final v = valueOf(b);
      if (v != null && v > 0) values[b.key] = v;
    }
    if (values.isEmpty) {
      return Center(
        child: Text('пока нет данных', style: theme.textTheme.bodySmall),
      );
    }
    final maxY = values.values.reduce((a, b) => a > b ? a : b) * 1.2;
    final labelStep = maxBars > 12 ? 6 : 1;
    return BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceBetween,
        barTouchData: BarTouchData(enabled: true),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              getTitlesWidget: (x, meta) {
                final i = x.toInt();
                if (labelOf == null && i % labelStep != 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    labelOf?.call(i) ?? '$i',
                    style: theme.textTheme.labelSmall,
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < maxBars; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i] ?? 0,
                  color: color,
                  width: maxBars > 12 ? 6 : 16,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
