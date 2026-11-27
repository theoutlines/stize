import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

part 'map_style_dataviz.dart';
part 'map_style_palette.dart';

/// The Stiže basemap ("Stiže Standard"): our own MapLibre style on MapTiler
/// vector tiles (OpenMapTiles schema), in light and dark.
///
/// Look: warm built-up land, blue-grey roads without casing, flat buildings
/// that rise into 3D on tilt, Serbian-Latin labels, POIs in coloured discs.
///
/// POIs are tiered by zoom: landmarks people navigate by from z15, everyday
/// places from z16, every named venue from z17 (future A→B endpoints). Stops
/// never come from the basemap: our own GTFS layers draw them.
///
/// Built here as a JSON string (raw JSON works on web, Android and iOS); the
/// POI sprite is `web/map/` (`tool/sprite/build-sprite.mjs`). The MapTiler key
/// is a client key injected via `--dart-define=MAPTILER_KEY`, never committed;
/// it is restricted by allowed origins in the MapTiler dashboard.
class MapStyle {
  const MapStyle._();

  static const _key = String.fromEnvironment('MAPTILER_KEY');

  /// Whether a MapTiler key was provided at build time.
  static bool get hasKey => _key.isNotEmpty;

  static final _json = <(bool, bool), String>{};

  /// The style for the app's light/dark theme; [dataviz] is the grey variant
  /// Coverage draws on (no POIs, no colour).
  static String forBrightness(Brightness b, {bool dataviz = false}) {
    final dark = b == Brightness.dark;
    return _json[(dark, dataviz)] ??= jsonEncode(
      _style(dark: dark, dataviz: dataviz),
    );
  }

  /// Where the POI sprite is served from. On web it is the app's own origin
  /// (previews included); native builds read it from production.
  static String _spriteBase() {
    if (kIsWeb) return '${Uri.base.origin}/map';
    return 'https://stize.app/map';
  }

  // ── Style ──────────────────────────────────────────────────────────────────

  static Map<String, Object?> _style({
    required bool dark,
    bool dataviz = false,
  }) {
    final c = dataviz
        ? (dark ? _darkDataviz : _lightDataviz)
        : (dark ? _dark : _light);
    const name = [
      'coalesce',
      ['get', 'name:sr-Latn'],
      ['get', 'name:latin'],
      ['get', 'name'],
    ];
    List<String> font(String w) => [
      w == 'b'
          ? 'Noto Sans Bold'
          : w == 'i'
          ? 'Noto Sans Italic'
          : 'Noto Sans Regular',
    ];
    List<Object> z(List<num> stops) => [
      'interpolate',
      ['exponential', 1.5],
      ['zoom'],
      ...stops,
    ];
    List<Object> cls(List<String> v) => [
      'match',
      ['get', 'class'],
      v,
      true,
      false,
    ];
    List<Object> sub(List<String> v) => [
      'match',
      ['get', 'subclass'],
      v,
      true,
      false,
    ];
    const notTunnel = [
      '!=',
      ['get', 'brunnel'],
      'tunnel',
    ];
    final label = {'text-halo-color': c.halo, 'text-halo-width': 1.5};

    Map<String, Object?> fill(
      String id,
      String layer,
      List<Object>? filter,
      String color, [
      Map<String, Object?> extra = const {},
    ]) => {
      'id': id,
      'type': 'fill',
      'source': 'omt',
      'source-layer': layer,
      'filter': ?filter,
      'paint': {'fill-color': color, ...extra},
    };
    Map<String, Object?> road(
      String id,
      List<Object> filter,
      String color,
      List<Object> width,
      num minzoom,
    ) => {
      'id': id,
      'type': 'line',
      'source': 'omt',
      'source-layer': 'transportation',
      'minzoom': minzoom,
      'filter': ['all', filter, notTunnel],
      'layout': {'line-cap': 'round', 'line-join': 'round'},
      'paint': {'line-color': color, 'line-width': width},
    };

    // POI tiers (OMT `rank` is unreliable: every clinic is rank 1, so tiers
    // filter by class/subclass instead).
    final known = [for (final g in _poiGroups) ...(g[0] as List<String>)];
    final poiColor = <Object>[
      'match',
      ['get', 'class'],
    ];
    for (final g in _poiGroups) {
      poiColor
        ..add(g[0])
        ..add(dark ? g[2] : g[1]);
    }
    poiColor.add(c.soft);
    const notTransit = [
      '!',
      [
        'match',
        ['get', 'subclass'],
        [
          'bus_stop',
          'tram_stop',
          'halt',
          'platform',
          'subway_entrance',
          'bus_station',
        ],
        true,
        false,
      ],
    ];
    final tiers = <(num, List<Object>)>[
      (
        15,
        [
          'any', // landmarks people navigate by
          cls([
            'museum',
            'theatre',
            'monument',
            'castle',
            'town_hall',
            'stadium',
            'zoo',
            'place_of_worship',
          ]),
          [
            'all',
            cls(['hospital']),
            sub(['hospital']),
          ],
          [
            'all',
            cls(['railway']),
            sub(['station']),
          ],
          [
            'all',
            cls(['college']),
            sub(['university']),
          ],
          [
            'all',
            cls(['shop', 'commercial']),
            sub(['mall', 'department_store']),
          ],
        ],
      ),
      (
        16,
        [
          'any', // everyday places
          cls([
            'lodging',
            'embassy',
            'post',
            'pharmacy',
            'police',
            'music',
            'park',
            'garden',
            'cinema',
            'attraction',
          ]),
          // Real libraries and galleries; bookshops (library/books) and street
          // artwork (art_gallery/artwork: murals, small sculptures, plaques)
          // wait for z17, where they serve as meeting points and A→B ends.
          [
            'all',
            cls(['library']),
            sub(['library']),
          ],
          [
            'all',
            cls(['art_gallery']),
            sub(['gallery', 'museum']),
          ],
          [
            'all',
            cls(['hospital']),
            [
              '!',
              sub(['hospital']),
            ],
          ],
          [
            'all',
            cls(['grocery']),
            sub(['supermarket']),
          ],
          [
            'all',
            cls(['college']),
            [
              '!',
              sub(['university']),
            ],
          ],
        ],
      ),
      (
        17,
        [
          'any', // every named venue: future A→B endpoints
          [
            'all',
            cls(['library']),
            sub(['books']),
          ],
          [
            'all',
            cls(['information']),
            sub(['office']),
          ],
          [
            'all',
            cls(['art_gallery']),
            sub(['artwork']),
          ],
          cls([
            'restaurant',
            'cafe',
            'bar',
            'fast_food',
            'beer',
            'ice_cream',
            'bakery',
            'shop',
            'grocery',
            'clothing_store',
            'florist',
            'gift',
            'school',
            'doctors',
            'dentist',
            'playground',
          ]),
        ],
      ),
    ];

    return {
      'version': 8,
      'name': 'Stize Standard ${dark ? 'dark' : 'light'}',
      'glyphs':
          'https://api.maptiler.com/fonts/{fontstack}/{range}.pbf?key=$_key',
      'sprite': '${_spriteBase()}/poi-${dark ? 'dark' : 'light'}',
      'sources': {
        'omt': {
          'type': 'vector',
          'url': 'https://api.maptiler.com/tiles/v3/tiles.json?key=$_key',
        },
      },
      'light': {
        'anchor': 'viewport',
        'color': '#FFFFFF',
        'intensity': c.light,
        'position': [1.15, 200, 35],
      },
      'layers': [
        {
          'id': 'bg',
          'type': 'background',
          'paint': {'background-color': c.bg},
        },
        fill(
          'built',
          'landuse',
          cls([
            'residential',
            'suburb',
            'neighbourhood',
            'commercial',
            'retail',
          ]),
          c.built,
        ),
        fill(
          'industrial',
          'landuse',
          cls(['industrial', 'railway', 'garages']),
          c.industrial,
        ),
        fill(
          'school',
          'landuse',
          cls(['school', 'university', 'college', 'kindergarten']),
          c.school,
        ),
        fill('hospital', 'landuse', cls(['hospital']), c.hospital),
        fill('wood', 'landcover', cls(['wood']), c.wood),
        fill(
          'grass',
          'landcover',
          cls(['grass', 'farmland', 'wetland']),
          c.grass,
        ),
        fill('park', 'park', null, c.park),
        fill(
          'pitch',
          'landuse',
          cls(['pitch', 'stadium', 'playground', 'cemetery']),
          c.pitch,
        ),
        fill('aeroway', 'aeroway', [
          '==',
          ['geometry-type'],
          'Polygon',
        ], c.industrial),
        fill('water', 'water', notTunnel, c.water),
        {
          'id': 'waterway',
          'type': 'line',
          'source': 'omt',
          'source-layer': 'waterway',
          'paint': {
            'line-color': c.water,
            'line-width': z([10, 0.6, 16, 3]),
          },
        },
        // Flat footprints: buildings read as texture until the camera tilts.
        fill('building-flat', 'building', null, c.flatBuilding, {
          'fill-outline-color': c.buildingLine,
          'fill-opacity': [
            'interpolate',
            ['linear'],
            ['zoom'],
            14,
            0,
            15,
            0.9,
          ],
        }),
        road('path', cls(['path']), c.path, z([15, 1, 18, 3]), 15),
        {
          'id': 'rail',
          'type': 'line',
          'source': 'omt',
          'source-layer': 'transportation',
          'minzoom': 12,
          'filter': [
            'all',
            cls(['rail', 'transit']),
            notTunnel,
          ],
          'paint': {
            'line-color': c.rail,
            'line-width': z([12, 0.8, 18, 2.5]),
            'line-dasharray': [4, 2],
          },
        },
        road(
          'road-minor',
          cls(['minor', 'service']),
          c.roadMinor,
          z([13, 0.6, 15, 2.5, 18, 14]),
          13,
        ),
        road(
          'road-tertiary',
          cls(['tertiary']),
          c.roadMinor,
          z([12, 0.8, 15, 4, 18, 18]),
          12,
        ),
        road(
          'road-major',
          cls(['primary', 'secondary']),
          c.roadMajor,
          z([9, 0.8, 15, 6, 18, 26]),
          9,
        ),
        road(
          'road-motor',
          cls(['motorway', 'trunk']),
          c.roadMotor,
          z([7, 0.8, 15, 7, 18, 30]),
          7,
        ),
        {
          'id': 'boundary',
          'type': 'line',
          'source': 'omt',
          'source-layer': 'boundary',
          'filter': [
            'all',
            [
              '<=',
              ['get', 'admin_level'],
              4,
            ],
            [
              '!=',
              ['get', 'maritime'],
              1,
            ],
          ],
          'paint': {
            'line-color': c.boundary,
            'line-width': 1,
            'line-dasharray': [3, 2],
          },
        },
        // 3D buildings: rise from z15 to z15.6; read as 3D only with pitch.
        {
          'id': 'building-3d',
          'type': 'fill-extrusion',
          'source': 'omt',
          'source-layer': 'building',
          'minzoom': 15,
          'paint': {
            'fill-extrusion-color': [
              'interpolate',
              ['linear'],
              [
                'coalesce',
                ['get', 'render_height'],
                10,
              ],
              0,
              c.wall,
              30,
              c.roof,
            ],
            'fill-extrusion-height': [
              'interpolate',
              ['linear'],
              ['zoom'],
              15,
              0,
              15.6,
              [
                'coalesce',
                ['get', 'render_height'],
                10,
              ],
            ],
            'fill-extrusion-base': [
              'coalesce',
              ['get', 'render_min_height'],
              0,
            ],
            'fill-extrusion-opacity': 0.95,
            'fill-extrusion-vertical-gradient': true,
          },
        },
        {
          'id': 'water-name',
          'type': 'symbol',
          'source': 'omt',
          'source-layer': 'water_name',
          'filter': [
            '==',
            ['geometry-type'],
            'LineString',
          ],
          'layout': {
            'text-field': name,
            'text-font': font('i'),
            'text-size': 13,
            'symbol-placement': 'line',
            'text-letter-spacing': 0.1,
          },
          'paint': {'text-color': c.waterText, ...label},
        },
        {
          'id': 'road-name',
          'type': 'symbol',
          'source': 'omt',
          'source-layer': 'transportation_name',
          'minzoom': 14,
          'filter': cls(['primary', 'secondary', 'tertiary', 'minor', 'trunk']),
          'layout': {
            'text-field': name,
            'text-font': font('b'),
            'symbol-placement': 'line',
            'text-transform': 'uppercase',
            'text-letter-spacing': 0.12,
            'text-size': z([14, 9, 18, 12]),
            'text-max-angle': 30,
          },
          'paint': {'text-color': c.road, ...label},
        },
        for (var i = 0; i < (dataviz ? 0 : tiers.length); i++)
          {
            'id': 'poi-tier-$i',
            'type': 'symbol',
            'source': 'omt',
            'source-layer': 'poi',
            'minzoom': tiers[i].$1,
            'filter': [
              'all',
              tiers[i].$2,
              cls(known),
              notTransit,
              ['has', 'name'],
            ],
            'layout': {
              'icon-image': [
                'concat',
                'poi-',
                ['get', 'class'],
              ],
              'text-field': name,
              'text-font': font('r'),
              'text-size': 11.5,
              'text-max-width': 8,
              'text-anchor': 'top',
              'text-offset': [0, 1.05],
              'text-optional': true,
              'symbol-sort-key': i,
              'icon-padding': 4,
            },
            'paint': {'text-color': poiColor, ...label},
          },
        {
          'id': 'place-quarter',
          'type': 'symbol',
          'source': 'omt',
          'source-layer': 'place',
          'minzoom': 12,
          'maxzoom': 16,
          'filter': cls(['suburb', 'quarter', 'neighbourhood']),
          'layout': {
            'text-field': name,
            'text-font': font('b'),
            'text-size': z([12, 11, 16, 14]),
            'text-max-width': 7,
          },
          'paint': {'text-color': c.soft, ...label},
        },
        {
          'id': 'place-city',
          'type': 'symbol',
          'source': 'omt',
          'source-layer': 'place',
          'maxzoom': 13,
          'filter': cls(['city', 'town']),
          'layout': {
            'text-field': name,
            'text-font': font('b'),
            'text-size': z([6, 12, 12, 20]),
          },
          'paint': {'text-color': c.text, ...label},
        },
      ],
    };
  }
}
