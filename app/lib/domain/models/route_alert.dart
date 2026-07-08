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
  final String summary;

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
    );
  }
}
