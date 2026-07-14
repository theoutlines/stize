import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre/maplibre.dart';

// Regression guard for the "bus stops don't render" bug (fix/stop-data):
// 19 Belgrade stops have a `"` in their name (e.g. `Park "Tašmajdan"`). geobase's
// `FeatureCollection.toText()` does NOT escape that quote, so the GeoJSON string
// it emits is invalid JSON; the maplibre-web plugin's
// `updateGeoJsonSource -> setData(JSON.parse(data))` then throws and the source
// stays empty. home_map_screen serialises stop sources with `jsonEncode` instead
// (which escapes correctly). These tests pin both facts down.
void main() {
  const quotedName = 'Park "Tašmajdan"';

  test('geobase toText() emits INVALID json for a quoted property (the bug)', () {
    final text = FeatureCollection([
      Feature<Point>(
        geometry: Point(Geographic(lon: 20.5, lat: 44.8)),
        properties: {'stopId': '20190', 'name': quotedName},
      ),
    ]).toText();
    // The inner quote is not escaped, so this cannot be parsed as JSON — exactly
    // what threw inside setData on the web.
    expect(() => jsonDecode(text), throwsFormatException);
  });

  test('jsonEncode serialisation stays valid and round-trips the quoted name', () {
    final text = jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [20.5, 44.8],
          },
          'properties': {'stopId': '20190', 'name': quotedName},
        },
      ],
    });
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    final feature = (decoded['features'] as List).single as Map<String, dynamic>;
    final props = feature['properties'] as Map<String, dynamic>;
    expect(props['name'], quotedName);
    expect(
      (feature['geometry'] as Map<String, dynamic>)['coordinates'],
      [20.5, 44.8],
    );
  });
}
