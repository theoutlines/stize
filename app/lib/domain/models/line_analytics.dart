/// One time-bucket of a line's rolled-up analytics (per hour-of-day or per
/// day-of-week). Means are null when there weren't enough samples to measure.
class AnalyticsBucket {
  const AnalyticsBucket({
    required this.key,
    required this.samples,
    required this.arrivals,
    required this.meanHeadwaySecs,
    required this.meanSpeedStopsPerMin,
  });

  final int key; // hour 0..23, or dow 0..6 (0 = Sunday)
  final int samples;
  final int arrivals;
  final double? meanHeadwaySecs;
  final double? meanSpeedStopsPerMin;

  factory AnalyticsBucket.fromJson(Map<String, dynamic> j) => AnalyticsBucket(
    key: (j['key'] as num).toInt(),
    samples: (j['samples'] as num?)?.toInt() ?? 0,
    arrivals: (j['arrivals'] as num?)?.toInt() ?? 0,
    meanHeadwaySecs: (j['mean_headway_secs'] as num?)?.toDouble(),
    meanSpeedStopsPerMin: (j['mean_speed_stops_per_min'] as num?)?.toDouble(),
  );
}

/// One (day-of-week, hour) cell of the full grid — the 2D shape the heatmap and
/// the distribution dot-plot need.
class AnalyticsCell {
  const AnalyticsCell({
    required this.dow,
    required this.hour,
    required this.samples,
    required this.arrivals,
    required this.meanHeadwaySecs,
    required this.meanSpeedStopsPerMin,
  });

  final int dow;
  final int hour;
  final int samples;
  final int arrivals;
  final double? meanHeadwaySecs;
  final double? meanSpeedStopsPerMin;

  factory AnalyticsCell.fromJson(Map<String, dynamic> j) => AnalyticsCell(
    dow: (j['dow'] as num).toInt(),
    hour: (j['hour'] as num).toInt(),
    samples: (j['samples'] as num?)?.toInt() ?? 0,
    arrivals: (j['arrivals'] as num?)?.toInt() ?? 0,
    meanHeadwaySecs: (j['mean_headway_secs'] as num?)?.toDouble(),
    meanSpeedStopsPerMin: (j['mean_speed_stops_per_min'] as num?)?.toDouble(),
  );
}

/// A line's analytics as served by `/api/v1/analytics/lines/:line`.
class LineAnalytics {
  const LineAnalytics({
    required this.line,
    required this.totalSamples,
    required this.byHour,
    required this.byDow,
    required this.grid,
    required this.updatedAt,
  });

  final String line;
  final int totalSamples;
  final List<AnalyticsBucket> byHour;
  final List<AnalyticsBucket> byDow;
  final List<AnalyticsCell> grid;
  final DateTime? updatedAt;

  /// Whether there's enough history to show anything meaningful yet.
  bool get hasData => totalSamples > 0;

  factory LineAnalytics.fromJson(Map<String, dynamic> j) {
    List<AnalyticsBucket> buckets(String key) => ((j[key] as List?) ?? const [])
        .map((e) => AnalyticsBucket.fromJson(e as Map<String, dynamic>))
        .toList();
    final ts = j['updated_at'];
    return LineAnalytics(
      line: (j['line'] as String?) ?? '',
      totalSamples: (j['total_samples'] as num?)?.toInt() ?? 0,
      byHour: buckets('by_hour'),
      byDow: buckets('by_dow'),
      grid: ((j['grid'] as List?) ?? const [])
          .map((e) => AnalyticsCell.fromJson(e as Map<String, dynamic>))
          .toList(),
      updatedAt: ts is num
          ? DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000)
          : null,
    );
  }
}
