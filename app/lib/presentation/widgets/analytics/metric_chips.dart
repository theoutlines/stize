import 'package:flutter/material.dart';

import '../../../domain/models/line_analytics.dart';

/// Compact summary chips above the charts — the key numbers for a line at a
/// glance (in the spirit of "Consistency 59%" / streak cards). Punctuality is
/// shown as a placeholder until it can be computed.
class MetricChips extends StatelessWidget {
  const MetricChips({super.key, required this.analytics});

  final LineAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final a = analytics;
    final headways = a.byHour.map((b) => b.meanHeadwaySecs).whereType<double>().toList();
    final speeds = a.byHour.map((b) => b.meanSpeedStopsPerMin).whereType<double>().toList();
    final activeHours = a.byHour.where((b) => b.samples > 0).length;
    AnalyticsBucket? peak;
    for (final b in a.byHour) {
      if (peak == null || b.samples > peak.samples) peak = b;
    }
    double? avg(List<double> xs) =>
        xs.isEmpty ? null : xs.reduce((x, y) => x + y) / xs.length;

    final meanHeadway = avg(headways);
    final meanSpeed = avg(speeds);

    final chips = <_Chip>[
      _Chip('Наблюдений', '${a.totalSamples}', Icons.dataset),
      _Chip(
        'Средний интервал',
        meanHeadway == null ? '—' : '${(meanHeadway / 60).toStringAsFixed(1)} мин',
        Icons.timelapse,
      ),
      _Chip(
        'Скорость',
        meanSpeed == null ? '—' : '${meanSpeed.toStringAsFixed(2)} ост/мин',
        Icons.speed,
      ),
      _Chip('Активных часов', '$activeHours/24', Icons.schedule),
      if (peak != null && peak.samples > 0)
        _Chip('Пик активности', '${peak.key}:00', Icons.trending_up),
      const _Chip('Пунктуальность', '—', Icons.query_stats),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [for (final c in chips) _ChipCard(chip: c)],
    );
  }
}

class _Chip {
  const _Chip(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

class _ChipCard extends StatelessWidget {
  const _ChipCard({required this.chip});
  final _Chip chip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(chip.icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(chip.label, style: theme.textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(chip.value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}
