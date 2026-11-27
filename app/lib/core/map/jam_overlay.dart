import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart' as ll;

import '../../domain/models/jam.dart';
import '../jam_geometry.dart';
import '../route_path.dart';

/// A direction's shape as the jam overlay needs it: the path to draw a stalled
/// segment along, and the coordinates of its stops by id.
typedef JamShape = ({RoutePath? path, Map<String, ll.LatLng> stops});

/// What the tram-jam overlay draws, and its pulse. Pure: the map screen feeds
/// it the active jams and their shapes and pushes the GeoJSON it returns.
///
/// Geometry gate: a jam that can't be placed on its route (off-shape) draws no
/// segment (wrong-street risk), but its affected stops still glow (the glow is
/// the primary visual, not a fallback) and its vehicles are badged.
class JamOverlay {
  JamOverlay._(this.segments, this.glowStops, this.jammedGarages);

  static JamOverlay get empty => JamOverlay._(const [], const [], const {});

  /// Build the overlay from [jams], given the shape of each jam's direction
  /// (by direction route_id; missing or null = unknown).
  factory JamOverlay.build(Iterable<Jam> jams, Map<String, JamShape?> shapes) {
    final segments = <List<ll.LatLng>>[];
    final glow = <ll.LatLng>[];
    final jammed = <String>{};
    for (final jam in jams) {
      final dir = jam.directionRouteId;
      final shape = dir == null ? null : shapes[dir];
      final seg = buildJamSegment(jam, shape?.path);
      if (seg.polyline != null) {
        segments.add(seg.polyline!);
      } else {
        for (final v in jam.vehicles) {
          jammed.add(v.garageNo);
        }
      }
      if (shape != null) {
        for (final id in jam.affectedStopIds) {
          final c = shape.stops[id];
          if (c != null) glow.add(c);
        }
      }
    }
    return JamOverlay._(segments, glow, jammed);
  }

  /// Amber polylines along the stalled stretches.
  final List<List<ll.LatLng>> segments;

  /// Affected stops, drawn as a soft glow.
  final List<ll.LatLng> glowStops;

  /// Garage numbers of vehicles in an off-shape jam: badged on the map.
  final Set<String> jammedGarages;

  /// Something to draw (the pulse runs only then).
  bool get isVisible => segments.isNotEmpty || glowStops.isNotEmpty;

  // ---- Pulse: a cheap opacity breath, 0.5 ↔ 1.0 over ~1.75 s -------------

  /// How often the pulse advances while a jam is shown.
  static const pulseTick = Duration(milliseconds: 90);
  static const _period = 1.75; // seconds per breath

  double _phase = 0; // 0..2π

  /// Advance the pulse by one [pulseTick].
  void advancePulse() {
    _phase = (_phase + 2 * math.pi * 0.09 / _period) % (2 * math.pi);
  }

  /// Carry the pulse over from the overlay this one replaces, so a refresh
  /// doesn't make the breath jump.
  void continuePulseFrom(JamOverlay previous) => _phase = previous._phase;

  double get pulseOpacity => 0.5 + 0.5 * (0.5 + 0.5 * math.sin(_phase));

  /// The segment lines, each carrying the current opacity.
  String segmentsGeoJson() {
    final o = segments.isEmpty ? 0.0 : pulseOpacity;
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        for (final seg in segments)
          {
            'type': 'Feature',
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                for (final p in seg) [p.longitude, p.latitude],
              ],
            },
            'properties': {'opacity': o},
          },
      ],
    });
  }

  /// The stop glows; they breathe a touch softer than the line.
  String glowGeoJson() {
    final o = glowStops.isEmpty ? 0.0 : pulseOpacity * 0.55;
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        for (final p in glowStops)
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [p.longitude, p.latitude],
            },
            'properties': {'opacity': o},
          },
      ],
    });
  }
}
