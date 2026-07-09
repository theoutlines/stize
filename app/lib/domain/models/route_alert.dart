class RouteAlert {
  const RouteAlert({
    required this.id,
    required this.url,
    required this.title,
    required this.publishedAt,
    required this.lines,
    required this.stops,
    required this.validFrom,
    required this.validUntil,
    required this.confidence,
    required this.summary,
    this.summaryEn,
    this.summaryRu,
  });

  final String id;
  final String url;
  final String title;
  final DateTime publishedAt;
  final List<String> lines;
  final List<String> stops;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final String confidence; // "line" | "stop"
  final String summary; // Serbian (source language)
  final String? summaryEn;
  final String? summaryRu;

  /// The summary in the app's language when available (H2), falling back to the
  /// Serbian source. Older alerts extracted before translations were added, and
  /// Serbian itself, use [summary].
  String localizedSummary(String languageCode) {
    switch (languageCode) {
      case 'ru':
        return summaryRu ?? summary;
      case 'en':
        return summaryEn ?? summary;
      default:
        return summary;
    }
  }

  /// Whether the change is in effect today (or has no stated period at all).
  bool get isActiveNow {
    final now = DateTime.now();
    if (validFrom != null && validFrom!.isAfter(now)) return false;
    if (validUntil != null && validUntil!.isBefore(now)) return false;
    return true;
  }

  /// A dated-but-not-yet-effective change — shown as a subtle heads-up rather
  /// than a full warning, per the project's "gentle until it's actually
  /// relevant" rule for future changes.
  bool get isUpcoming {
    final now = DateTime.now();
    return validFrom != null && validFrom!.isAfter(now);
  }

  bool get isExpired {
    final now = DateTime.now();
    return validUntil != null && validUntil!.isBefore(now);
  }

  /// Rough severity split for tone (H3): most route changes are routine and
  /// should read calmly; only genuine disruptions (a line suspended / not
  /// running, an extraordinary regime) get the louder treatment. Heuristic on
  /// the Serbian source text — good enough for an experimental feed.
  bool get isHighSeverity {
    final t = '$title $summary'.toLowerCase();
    const keywords = [
      'obustav', // obustava/obustavlja — suspension
      'ne saobra', // ne saobraća — not operating
      'ukida', // cancels
      'vanredn', // vanredno — extraordinary
      'zabran', // zabrana — ban/closure
    ];
    return keywords.any(t.contains);
  }

  bool matchesLine(String line) {
    return lines.any((l) => l.toLowerCase() == line.toLowerCase());
  }

  bool matchesStopName(String stopName) {
    if (confidence != 'stop') return false;
    final needle = stopName.toLowerCase();
    return stops.any((s) => s.toLowerCase().contains(needle) || needle.contains(s.toLowerCase()));
  }

  factory RouteAlert.fromJson(Map<String, dynamic> json) {
    return RouteAlert(
      id: json['id'] as String,
      url: json['url'] as String,
      title: json['title'] as String,
      publishedAt: DateTime.parse(json['publishedAt'] as String),
      lines: (json['lines'] as List<dynamic>).cast<String>(),
      stops: (json['stops'] as List<dynamic>).cast<String>(),
      validFrom: json['validFrom'] != null ? DateTime.tryParse(json['validFrom'] as String) : null,
      validUntil: json['validUntil'] != null ? DateTime.tryParse(json['validUntil'] as String) : null,
      confidence: json['confidence'] as String,
      summary: json['summary'] as String,
      summaryEn: json['summaryEn'] as String?,
      summaryRu: json['summaryRu'] as String?,
    );
  }
}
