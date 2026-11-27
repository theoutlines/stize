class GeocodeResult {
  const GeocodeResult({
    required this.displayName,
    required this.lat,
    required this.lon,
    this.kind,
  });

  final String displayName;
  final double lat;
  final double lon;

  /// The map's POI class for a named place ("museum", "park"), shown as the
  /// same badge the place has on the map. Null for a street or an address.
  final String? kind;

  factory GeocodeResult.fromJson(Map<String, dynamic> json) {
    return GeocodeResult(
      displayName: json['display_name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      kind: json['kind'] as String?,
    );
  }
}
