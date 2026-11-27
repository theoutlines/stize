part of 'map_style.dart';

// The data the style is built from: the light and dark palettes, the POI
// groups (which classes get which colour) and the palette type.

const _light = _Palette(
  bg: '#F3F0EC',
  built: '#F7E7DA',
  industrial: '#EFEBE8',
  school: '#F3E9DC',
  hospital: '#F8E1E0',
  water: '#A9CFF2',
  waterText: '#4D7AA8',
  park: '#CDEBC0',
  wood: '#C3E3B4',
  grass: '#D6ECCB',
  pitch: '#BFE3AE',
  roadMinor: '#D3D8E4',
  roadMajor: '#BCC3D6',
  roadMotor: '#AAB3CB',
  path: '#FFFFFF',
  rail: '#C7C9D1',
  roof: '#F4E9DF',
  wall: '#E9DCCF',
  flatBuilding: '#EFE0D2',
  buildingLine: '#E6D5C6',
  text: '#2F3542',
  road: '#59617A',
  soft: '#6E7586',
  halo: 'rgba(255,255,255,0.95)',
  boundary: '#C9BFD3',
  light: 0.28,
);

const _dark = _Palette(
  bg: '#191D27',
  built: '#1F2330',
  industrial: '#1C202A',
  school: '#21232D',
  hospital: '#2A2029',
  water: '#0C1A2C',
  waterText: '#6F93BF',
  park: '#1A2B26',
  wood: '#182822',
  grass: '#1C2B27',
  pitch: '#1D3027',
  roadMinor: '#2C3343',
  roadMajor: '#394257',
  roadMotor: '#465170',
  path: '#2A303E',
  rail: '#3A4152',
  roof: '#2A2F3D',
  wall: '#232836',
  flatBuilding: '#252A37',
  buildingLine: '#1E2230',
  text: '#DCE1EA',
  road: '#9BA4B8',
  soft: '#8F97A8',
  halo: 'rgba(22,26,35,0.92)',
  boundary: '#433D52',
  light: 0.18,
);

/// POI categories → label colour (light, dark). Must match the disc colours
/// in the sprite. No red, blue or orange: those hues belong to tram, bus and
/// trolleybus lines.
const _poiGroups = <List<Object>>[
  [
    [
      'museum',
      'theatre',
      'art_gallery',
      'cinema',
      'library',
      'attraction',
      'monument',
      'castle',
      'music',
    ],
    '#A24DB3',
    '#C08BCF',
  ],
  [
    [
      'place_of_worship',
      'religious_christian',
      'religious_jewish',
      'religious_muslim',
    ],
    '#7C6E61',
    '#A89D93',
  ],
  [
    ['hospital', 'pharmacy', 'doctors', 'dentist'],
    '#C23E66',
    '#DE7E9A',
  ],
  [
    ['college', 'school'],
    '#7E6D44',
    '#ADA07E',
  ],
  [
    ['town_hall', 'embassy', 'police', 'post', 'information'],
    '#556078',
    '#9AA3B5',
  ],
  [
    [
      'shop',
      'grocery',
      'clothing_store',
      'commercial',
      'bakery',
      'florist',
      'gift',
    ],
    '#24807C',
    '#6DB2AE',
  ],
  [
    ['restaurant', 'cafe', 'bar', 'fast_food', 'beer', 'ice_cream'],
    '#94740F',
    '#CDB36A',
  ],
  [
    ['lodging'],
    '#5257C2',
    '#9497DD',
  ],
  [
    ['park', 'garden', 'playground', 'zoo', 'stadium'],
    '#357A42',
    '#7FB98A',
  ],
  [
    ['railway'],
    '#4C5568',
    '#9AA2B3',
  ],
];

class _Palette {
  const _Palette({
    required this.bg,
    required this.built,
    required this.industrial,
    required this.school,
    required this.hospital,
    required this.water,
    required this.waterText,
    required this.park,
    required this.wood,
    required this.grass,
    required this.pitch,
    required this.roadMinor,
    required this.roadMajor,
    required this.roadMotor,
    required this.path,
    required this.rail,
    required this.roof,
    required this.wall,
    required this.flatBuilding,
    required this.buildingLine,
    required this.text,
    required this.road,
    required this.soft,
    required this.halo,
    required this.boundary,
    required this.light,
  });

  final String bg,
      built,
      industrial,
      school,
      hospital,
      water,
      waterText,
      park,
      wood,
      grass,
      pitch;
  final String roadMinor,
      roadMajor,
      roadMotor,
      path,
      rail,
      roof,
      wall,
      flatBuilding,
      buildingLine;
  final String text, road, soft, halo, boundary;
  final double light;
}
