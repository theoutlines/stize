/// GPU symbol layer for **typed moving objects** on the map.
///
/// This is deliberately not a "bus layer": an object carries a [MovingObjectKind]
/// and every rendering choice (colour, glyph, and — later — behaviour) is a
/// data-driven MapLibre expression keyed on that kind. Adding metro, trains, or
/// micromobility is a new enum value + a colour arm + a registered glyph image;
/// the source, the layers, and the tap/spiderfy logic don't change. Objects from
/// other backends can flow into the same source as long as they map to a kind.
///
/// The heavy per-object Flutter widget path (`VehicleMarker`/`WidgetLayer`) stays
/// as a fallback behind the `symbol_layer` flag — see `home_map_screen.dart`.
/// Here everything is batched into one GeoJSON source rendered on the GPU, so
/// the cost is sub-linear in object count (40 or 400 symbols ≈ one price).
///
/// **Identity is intentionally NOT on the marker.** A feature carries only what
/// the map needs to draw and to route a tap: the tracking [MovingObject.key], the
/// [MovingObject.kind], a short [MovingObject.label] (the line number), the
/// travel [MovingObject.heading], and the `selected`/`stuck` state. The fleet id
/// and all rich identity live in the tap sheet, never on the symbol.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre/maplibre.dart';

import '../domain/models/vehicle_source.dart';
import '../domain/models/vehicle_type.dart';
import '../presentation/widgets/vehicle_icon.dart';

// ---- Typed moving object ----------------------------------------------------

/// The kind of a moving object. Bus/tram/trolleybus today; metro, train, and
/// micromobility (scooter/bike) are reserved so the layer is ready for the
/// roadmap without a rewrite. Unknown/未mapped kinds render with the bus styling.
enum MovingObjectKind {
  bus,
  tram,
  trolleybus,
  metro,
  train,
  scooter,
  bike;

  /// The value written into the GeoJSON `kind` property and matched by the
  /// data-driven style expressions.
  String get id => name;

  /// Map the current transit [VehicleType] onto a kind. The broader kinds have
  /// no VehicleType yet — they'll arrive with their own data source.
  static MovingObjectKind fromVehicleType(VehicleType type) => switch (type) {
    VehicleType.bus => MovingObjectKind.bus,
    VehicleType.tram => MovingObjectKind.tram,
    VehicleType.trolleybus => MovingObjectKind.trolleybus,
  };
}

/// A single typed moving object to draw on the symbol layer. Immutable and
/// widget-free so the feature-building logic is unit-testable without a map.
@immutable
class MovingObject {
  const MovingObject({
    required this.key,
    required this.position,
    required this.kind,
    required this.label,
    this.heading,
    this.selected = false,
    this.stuck = false,
    this.opacity = 1.0,
    this.moving = true,
    this.source = VehicleSource.live,
  });

  /// Stable tracking id (e.g. garage number). Used to route a tap and to group
  /// coincident objects for spiderfy — **not** shown on the marker.
  final String key;

  final ll.LatLng position;
  final MovingObjectKind kind;

  /// Short text drawn on the coin — the line number today. Generic on purpose:
  /// a future kind might carry a train/run number instead.
  final String label;

  /// Travel direction in degrees (0 = north, clockwise); null when unknown, in
  /// which case the direction arrow is omitted (heading defaults to 0 in props).
  final double? heading;

  final bool selected;
  final bool stuck;

  /// Draw opacity 0..1. Fades a vanishing/stale vehicle out over its grace period
  /// (rather than holding it standing) and dims a moving vehicle while it crosses
  /// another so the overlap reads as two passing, not one.
  final double opacity;

  /// Whether the vehicle currently has forward motion. Not written to the layer
  /// — it only decides arrangement: stationary coincident vehicles are fanned
  /// out, moving ones pass through each other.
  final bool moving;

  /// Live vs GTFS-schedule-predicted. Not written to the layer — the scheduled
  /// dimming is folded into [opacity]; this only orders z (live drawn on top).
  final VehicleSource source;
}

/// Baseline draw opacity of a scheduled (timetable-predicted) object, so it
/// reads clearly as "by schedule, not a live position" while staying legible.
/// Combined with the grace/crossing fades. Live objects render at full opacity.
const double kScheduledBaseOpacity = 0.5;

// ---- Source / layer ids -----------------------------------------------------

const String movingObjectsSourceId = 'moving-objects-src';
const String movingObjectsBadgeLayerId = 'moving-objects-badge';
const String movingObjectsArrowLayerId = 'moving-objects-arrow';
const String movingObjectsLabelLayerId = 'moving-objects-label';

/// The layer ids a tap should query, most-specific first. The badge covers every
/// zoom (it's the dot far out and the coin up close), so it alone is enough.
const List<String> movingObjectsTapLayerIds = [movingObjectsBadgeLayerId];

/// At/above this zoom the full coin (glyph + number + direction arrow) is drawn;
/// below it only the coloured badge dot shows (progressive detail, on the GPU —
/// no Flutter rebuild on zoom). Mirrors the widget path's dot→pill threshold.
const double kMovingObjectDetailZoom = 15.5;

// ---- Registered glyph/arrow image ids ---------------------------------------

class MovingObjectImages {
  const MovingObjectImages._();

  static const arrow = 'stg-mo-arrow';
  static const glyphBus = 'stg-mo-glyph-bus';
  static const glyphTram = 'stg-mo-glyph-tram';
  static const glyphTrolley = 'stg-mo-glyph-trolley';

  /// The registered glyph id for a kind. Kinds without dedicated art yet fall
  /// back to the bus glyph (their badge colour still tells them apart).
  static String glyphFor(MovingObjectKind kind) => switch (kind) {
    MovingObjectKind.tram => glyphTram,
    MovingObjectKind.trolleybus => glyphTrolley,
    _ => glyphBus,
  };
}

// ---- Palette (mirrors map_support.dart) -------------------------------------
//
// Kept as hex strings for the data-driven `circle-color` expression. The values
// mirror map_support.dart's vehicle colours so a symbol and its line's stops
// read as the same type; the reserved kinds get distinct hues for later.

const String _busHex = '#1B67C4'; // transit blue
const String _trolleyHex = '#EF7B22'; // orange
const String _tramHex = '#D3342B'; // tram red
const String _metroHex = '#7A3FB0'; // reserved: metro purple
const String _trainHex = '#2E7D32'; // reserved: train green
const String _microHex = '#0E9AA7'; // reserved: scooter/bike teal
const String _stuckHex = '#B00842'; // "looks stuck" crimson (≠ tram red)
const String _selectedRingHex = '#0F172A'; // dark ring on the selected object

/// `circle-color` expression: kind → hex, stuck objects overridden to crimson.
List<Object> _badgeColorExpression() => [
  'case',
  ['get', 'stuck'],
  _stuckHex,
  [
    'match',
    ['get', 'kind'],
    'tram', _tramHex,
    'trolleybus', _trolleyHex,
    'metro', _metroHex,
    'train', _trainHex,
    'scooter', _microHex,
    'bike', _microHex,
    _busHex, // default: bus + any unknown kind
  ],
];

// ---- Pure GeoJSON building (unit-tested) ------------------------------------

/// Builds the FeatureCollection (as a Dart map) fed to the symbol source. Pure —
/// no map, no widgets — so tests pin the coordinate order and property set.
///
/// Coordinates follow the GeoJSON spec: **[lon, lat]**. Properties are the
/// minimal set the layer styles read; the fleet id / identity is deliberately
/// absent (it lives in the tap sheet).
Map<String, dynamic> movingObjectsFeatureCollection(
  Iterable<MovingObject> objects,
) {
  return {
    'type': 'FeatureCollection',
    'features': [
      for (final o in objects)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [o.position.longitude, o.position.latitude],
          },
          'properties': {
            'key': o.key,
            'kind': o.kind.id,
            'label': o.label,
            'heading': o.heading ?? 0,
            'selected': o.selected,
            'stuck': o.stuck,
            'opacity': o.opacity,
          },
        },
    ],
  };
}

/// The FeatureCollection as a JSON string, ready for
/// `StyleController.updateGeoJsonSource(id: movingObjectsSourceId, data: …)`.
String movingObjectsGeoJson(Iterable<MovingObject> objects) =>
    jsonEncode(movingObjectsFeatureCollection(objects));

// NB: arrangement of co-located vehicles (fan out stationary clusters; pass
// moving ones through each other with a crossing fade) is *stateful* — it eases
// across frames and reads the animator's per-vehicle motion — so it lives in the
// map screen (`_arrangeVehicles`), not here. This module stays pure: model +
// GeoJSON + layer specs.

// ---- Source + layer specs ---------------------------------------------------

/// The (initially empty) GeoJSON source the symbol layers read. Positions are
/// pushed in later via `updateGeoJsonSource`.
GeoJsonSource movingObjectsSource() => const GeoJsonSource(
  id: movingObjectsSourceId,
  data: '{"type":"FeatureCollection","features":[]}',
);

/// The coloured badge: a filled circle keyed on kind. It's the far-zoom dot and
/// the base of the up-close coin, and the single tap target across all zooms.
/// A selected object gets a thicker dark ring; a stuck one turns crimson.
CircleStyleLayer movingObjectsBadgeLayer() => CircleStyleLayer(
  id: movingObjectsBadgeLayerId,
  sourceId: movingObjectsSourceId,
  paint: {
    'circle-color': _badgeColorExpression(),
    'circle-opacity': <Object>['get', 'opacity'],
    'circle-stroke-opacity': <Object>['get', 'opacity'],
    'circle-radius': <Object>[
      'interpolate',
      ['linear'],
      ['zoom'],
      11, 4.0,
      14, 7.0,
      kMovingObjectDetailZoom, 13.0,
      18, 15.0,
    ],
    'circle-stroke-width': <Object>[
      'case',
      ['get', 'selected'],
      3.0,
      1.5,
    ],
    'circle-stroke-color': <Object>[
      'case',
      ['get', 'selected'],
      _selectedRingHex,
      '#ffffff',
    ],
  },
);

/// The direction arrow: a small triangle rotated to the object's heading and
/// pushed outward along travel. Detail-zoom only; omitted where heading is 0
/// (unknown) so a directionless object isn't given a false north arrow.
SymbolStyleLayer movingObjectsArrowLayer() => SymbolStyleLayer(
  id: movingObjectsArrowLayerId,
  sourceId: movingObjectsSourceId,
  minZoom: kMovingObjectDetailZoom,
  filter: <Object>[
    '!=',
    ['get', 'heading'],
    0,
  ],
  layout: {
    'icon-image': MovingObjectImages.arrow,
    'icon-size': 0.5,
    'icon-rotate': <Object>['get', 'heading'],
    'icon-rotation-alignment': 'map',
    'icon-offset': <Object>[0, -34],
    'icon-allow-overlap': true,
    'icon-ignore-placement': true,
  },
  paint: {'icon-opacity': <Object>['get', 'opacity']},
);

/// The coin's content: the type glyph stacked above the line number, both drawn
/// at the object's point. Detail-zoom only. The glyph anchors above centre and
/// the number below it, so together they sit inside the badge like the widget
/// pill. Overlap is allowed so neither is ever collision-dropped.
SymbolStyleLayer movingObjectsLabelLayer() => SymbolStyleLayer(
  id: movingObjectsLabelLayerId,
  sourceId: movingObjectsSourceId,
  minZoom: kMovingObjectDetailZoom,
  layout: {
    'icon-image': <Object>[
      'match',
      ['get', 'kind'],
      'tram', MovingObjectImages.glyphTram,
      'trolleybus', MovingObjectImages.glyphTrolley,
      MovingObjectImages.glyphBus, // default (bus + reserved kinds for now)
    ],
    'icon-size': 0.42,
    'icon-anchor': 'bottom',
    'icon-offset': <Object>[0, 2],
    'icon-allow-overlap': true,
    'icon-ignore-placement': true,
    'text-field': <Object>['get', 'label'],
    'text-font': <String>['Open Sans Regular', 'Arial Unicode MS Regular'],
    'text-size': 12.0,
    'text-anchor': 'top',
    'text-offset': <Object>[0, 0.05],
    'text-allow-overlap': true,
    'text-ignore-placement': true,
  },
  paint: {
    'text-color': '#ffffff',
    'text-halo-color': 'rgba(0,0,0,0.45)',
    'text-halo-width': 1.2,
    'text-opacity': <Object>['get', 'opacity'],
    'icon-opacity': <Object>['get', 'opacity'],
  },
);

// ---- Image registration -----------------------------------------------------

/// (Re)registers the glyph and arrow images the symbol layers reference. Must be
/// called on each style (re)load, alongside `registerStigmaImages`, because a
/// style reload drops previously added images.
Future<void> registerMovingObjectImages(StyleController style) async {
  await Future.wait([
    style.addImageFromWidget(
      id: MovingObjectImages.glyphBus,
      widget: _glyphImage(VehicleType.bus),
    ),
    style.addImageFromWidget(
      id: MovingObjectImages.glyphTram,
      widget: _glyphImage(VehicleType.tram),
    ),
    style.addImageFromWidget(
      id: MovingObjectImages.glyphTrolley,
      widget: _glyphImage(VehicleType.trolleybus),
    ),
    style.addImageFromWidget(
      id: MovingObjectImages.arrow,
      widget: const _ArrowImage(),
    ),
  ]);
}

/// A white type glyph on a transparent square, captured as a symbol image.
Widget _glyphImage(VehicleType type) => SizedBox(
  width: 32,
  height: 32,
  child: Center(child: vehicleGlyph(type, size: 26, color: Colors.white)),
);

/// The direction arrow image: a white triangle with a dark outline (reads on any
/// badge colour and on the map), apex pointing up (north) before rotation.
class _ArrowImage extends StatelessWidget {
  const _ArrowImage();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 24,
    height: 24,
    child: Center(
      child: SizedBox(width: 18, height: 14, child: CustomPaint(painter: _ArrowPainter())),
    ),
  );
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xCC0F172A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) => false;
}
