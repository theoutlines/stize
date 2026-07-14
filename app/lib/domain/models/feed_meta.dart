/// Freshness metadata for the GTFS reference bundle, from `/api/v1/gtfs-meta`.
/// Used to show a `Route data: <date>` line so the user (and we) can tell how
/// current the schedule reference is. All fields are optional — an older bundle
/// or a partial feed may omit them, and the UI degrades silently.
class FeedMeta {
  const FeedMeta({
    this.feedVersion,
    this.feedStartDate,
    this.feedEndDate,
    this.builtAt,
  });

  final String? feedVersion;
  final DateTime? feedStartDate;
  final DateTime? feedEndDate;
  final DateTime? builtAt;

  static DateTime? _parse(Object? v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v);
  }

  factory FeedMeta.fromJson(Map<String, dynamic> json) {
    return FeedMeta(
      feedVersion: json['feed_version'] as String?,
      feedStartDate: _parse(json['feed_start_date']),
      feedEndDate: _parse(json['feed_end_date']),
      builtAt: _parse(json['built_at']),
    );
  }
}
