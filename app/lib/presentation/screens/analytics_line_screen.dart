import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/line_analytics.dart';
import '../providers/providers.dart';
import '../widgets/analytics/analytics_palette.dart';
import '../widgets/analytics/distribution_dots.dart';
import '../widgets/analytics/hourly_sparkline.dart';
import '../widgets/analytics/metric_chips.dart';
import '../widgets/analytics/time_heatmap.dart';

/// Draft analytics screen for one line. Each metric gets the visualisation type
/// that fits it: heatmaps for time-of-day reliability, a sparkline for hourly
/// trends / line comparison, a dot-plot for the interval distribution, and
/// summary chips on top. Visual is rough on purpose — the point is the right
/// chart type per metric, built from real accumulated data. Gated behind the
/// remote `analytics_show` flag.
class AnalyticsLineScreen extends ConsumerStatefulWidget {
  const AnalyticsLineScreen({super.key, required this.line});

  final String line;

  @override
  ConsumerState<AnalyticsLineScreen> createState() => _AnalyticsLineScreenState();
}

class _AnalyticsLineScreenState extends ConsumerState<AnalyticsLineScreen> {
  String? _compare;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(lineAnalyticsProvider(widget.line));
    return Scaffold(
      appBar: AppBar(title: Text('Аналитика · линия ${widget.line}')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const _Message(
          icon: Icons.cloud_off,
          title: 'Не удалось загрузить',
          body: 'Попробуй позже.',
        ),
        data: (a) => a.hasData ? _charts(context, a) : _emptyState(context, a),
      ),
    );
  }

  Widget _charts(BuildContext context, LineAnalytics a) {
    final theme = Theme.of(context);
    final compareAsync = _compare != null
        ? ref.watch(lineAnalyticsProvider(_compare!))
        : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Наблюдений: ${a.totalSamples}'
          '${a.updatedAt != null ? ' · обновлено ${_ago(a.updatedAt!)}' : ''}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        MetricChips(analytics: a),
        const SizedBox(height: 4),

        // Punctuality — its home is a heatmap; shown as a pale placeholder grid
        // (same visual language) until it can be computed from GTFS schedule.
        _Card(
          title: 'Пунктуальность · час × день',
          subtitle: 'скоро — считается относительно расписания GTFS',
          child: TimeHeatmap(grid: a.grid, valueOf: (_) => null),
        ),

        // Real interval as a reliability heatmap (green = runs often).
        _Card(
          title: 'Реальный интервал · час × день',
          subtitle: 'минуты между машинами',
          child: Column(
            children: [
              TimeHeatmap(
                grid: a.grid,
                valueOf: (c) => c.meanHeadwaySecs,
                lowerIsBetter: true,
              ),
              const SizedBox(height: 10),
              const _ReliabilityLegend(lowLabel: 'чаще', highLabel: 'реже'),
            ],
          ),
        ),

        // Hourly profile as a sparkline — with an optional second line to
        // compare on the same axis.
        _Card(
          title: 'Профиль по часам',
          subtitle:
              'число наблюдений по часам${_compare != null ? ' · сравнение линий' : ''}',
          trailing: _compareControl(context),
          child: HourlySparkline(
            series: [
              HourlySeries(
                label: 'линия ${a.line}',
                color: AnalyticsPalette.seriesA,
                byHour: a.byHour,
                valueOf: (b) => b.samples.toDouble(),
              ),
              if (compareAsync?.valueOrNull != null)
                HourlySeries(
                  label: 'линия ${compareAsync!.value!.line}',
                  color: AnalyticsPalette.seriesB,
                  byHour: compareAsync.value!.byHour,
                  valueOf: (b) => b.samples.toDouble(),
                ),
            ],
          ),
        ),

        // Interval distribution as a dot cloud (spread + data density).
        _Card(
          title: 'Распределение интервалов',
          subtitle: 'точка = слот (час×день); размер = объём данных',
          child: DistributionDots(grid: a.grid),
        ),

        const SizedBox(height: 4),
        Text(
          'Черновой экран. Каждая метрика показана подходящим типом графика; '
          'данные реальные и уточняются по мере накопления истории.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }

  Widget _compareControl(BuildContext context) {
    if (_compare != null) {
      return ActionChip(
        avatar: const Icon(Icons.close, size: 16),
        label: Text('линия $_compare'),
        onPressed: () => setState(() => _compare = null),
      );
    }
    return TextButton.icon(
      icon: const Icon(Icons.compare_arrows, size: 18),
      label: const Text('Сравнить'),
      onPressed: () async {
        final other = await _askLine(context);
        if (other != null && other.isNotEmpty && other != widget.line) {
          setState(() => _compare = other);
        }
      },
    );
  }

  Future<String?> _askLine(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сравнить с линией'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'номер линии, напр. 5'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Ок'),
          ),
        ],
      ),
    );
  }

  // Empty state in the same visual language: a pale, empty heatmap grid with a
  // humane caption — the shape is ready, data is still accumulating.
  Widget _emptyState(BuildContext context, LineAnalytics a) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Card(
          title: 'Аналитика · час × день',
          subtitle: 'копим данные',
          child: TimeHeatmap(grid: const [], valueOf: (_) => null),
        ),
        const SizedBox(height: 8),
        Center(
          child: Column(
            children: [
              Icon(Icons.hourglass_bottom, size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text('Данных пока мало', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Мы только начали копить историю по этой линии. '
                'Загляни позже — сетки и графики наполнятся со временем.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
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

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _ReliabilityLegend extends StatelessWidget {
  const _ReliabilityLegend({required this.lowLabel, required this.highLabel});
  final String lowLabel;
  final String highLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(lowLabel, style: theme.textTheme.labelSmall),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                colors: [
                  AnalyticsPalette.reliability(0),
                  AnalyticsPalette.reliability(0.5),
                  AnalyticsPalette.reliability(1),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(highLabel, style: theme.textTheme.labelSmall),
      ],
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
