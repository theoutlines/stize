class Stop {
  const Stop({
    required this.stopId,
    required this.name,
    required this.lat,
    required this.lon,
    required this.lines,
  });

  final String stopId;
  final String name;
  final double lat;
  final double lon;
  final List<String> lines;

  factory Stop.fromJson(Map<String, dynamic> json) {
    return Stop(
      stopId: json['stop_id'] as String,
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      lines: (json['lines'] as List<dynamic>).cast<String>(),
    );
  }
}
