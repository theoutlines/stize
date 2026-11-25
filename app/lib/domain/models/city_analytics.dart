/// The city section's summary, as served by `/api/v1/analytics/city`. Weekday
/// and hour are Belgrade time. Means are null when nothing was measured.
class CityCell {
  const CityCell({
    required this.dow,
    required this.hour,
    required this.arrivals,
    required this.delayCount,
    required this.meanDelaySecs,
    required this.headwayCount,
    required this.meanHeadwaySecs,
  });

  final int dow; // 0 = Sunday
  final int hour;
  final int arrivals;
  final int delayCount;
  final int? meanDelaySecs;
  final int headwayCount;
  final int? meanHeadwaySecs;

  factory CityCell.fromJson(Map<String, dynamic> j) => CityCell(
    dow: (j['dow'] as num).toInt(),
    hour: (j['hour'] as num).toInt(),
    arrivals: (j['arrivals'] as num?)?.toInt() ?? 0,
    delayCount: (j['delay_count'] as num?)?.toInt() ?? 0,
    meanDelaySecs: (j['mean_delay_secs'] as num?)?.toInt(),
    headwayCount: (j['headway_count'] as num?)?.toInt() ?? 0,
    meanHeadwaySecs: (j['mean_headway_secs'] as num?)?.toInt(),
  );
}

class CityLine {
  const CityLine({
    required this.line,
    required this.arrivals,
    required this.delayCount,
    required this.meanDelaySecs,
    required this.headwayCount,
    required this.meanHeadwaySecs,
    required this.eveningHeadwayCount,
    required this.eveningMeanHeadwaySecs,
  });

  final String line;
  final int arrivals;
  final int delayCount;
  final int? meanDelaySecs;
  final int headwayCount;
  final int? meanHeadwaySecs;
  final int eveningHeadwayCount;
  final int? eveningMeanHeadwaySecs;

  factory CityLine.fromJson(Map<String, dynamic> j) => CityLine(
    line: '${j['line']}',
    arrivals: (j['arrivals'] as num?)?.toInt() ?? 0,
    delayCount: (j['delay_count'] as num?)?.toInt() ?? 0,
    meanDelaySecs: (j['mean_delay_secs'] as num?)?.toInt(),
    headwayCount: (j['headway_count'] as num?)?.toInt() ?? 0,
    meanHeadwaySecs: (j['mean_headway_secs'] as num?)?.toInt(),
    eveningHeadwayCount: (j['evening_headway_count'] as num?)?.toInt() ?? 0,
    eveningMeanHeadwaySecs: (j['evening_mean_headway_secs'] as num?)?.toInt(),
  );
}

class CitySummary {
  const CitySummary({
    required this.arrivals,
    required this.delayCount,
    required this.meanDelaySecs,
    required this.headwayCount,
    required this.meanHeadwaySecs,
    required this.grid,
    required this.lines,
    required this.aggregatedTo,
  });

  final int arrivals;
  final int delayCount;
  final int? meanDelaySecs;
  final int headwayCount;
  final int? meanHeadwaySecs;
  final List<CityCell> grid;
  final List<CityLine> lines;
  final DateTime? aggregatedTo;

  factory CitySummary.fromJson(Map<String, dynamic> j) {
    final t = (j['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
    final at = j['aggregated_to'];
    return CitySummary(
      arrivals: (t['arrivals'] as num?)?.toInt() ?? 0,
      delayCount: (t['delay_count'] as num?)?.toInt() ?? 0,
      meanDelaySecs: (t['mean_delay_secs'] as num?)?.toInt(),
      headwayCount: (t['headway_count'] as num?)?.toInt() ?? 0,
      meanHeadwaySecs: (t['mean_headway_secs'] as num?)?.toInt(),
      grid: ((j['grid'] as List?) ?? const [])
          .map((e) => CityCell.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      lines: ((j['lines'] as List?) ?? const [])
          .map((e) => CityLine.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      aggregatedTo: at is num
          ? DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000)
          : null,
    );
  }
}

/// Sample minimums: below them a number is not shown (honesty rule from
/// the transport analytics spec (internal)). Owner-approved 2026-11-23.
const kCityCellMinSamples = 10;
const kCityLineMinSamples = 30;
