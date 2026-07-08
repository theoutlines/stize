class GeocodeResult {
  const GeocodeResult({required this.displayName, required this.lat, required this.lon});

  final String displayName;
  final double lat;
  final double lon;

  factory GeocodeResult.fromJson(Map<String, dynamic> json) {
    return GeocodeResult(
      displayName: json['display_name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
    );
  }
}
