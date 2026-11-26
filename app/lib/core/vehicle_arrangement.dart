import 'dart:math' as math;

import 'package:latlong2/latlong.dart' as ll;

import 'moving_object_layer.dart';

/// Lays out the vehicle markers for the symbol source. Keeps its own eased
/// state between frames (fan offsets, crossing dims), so one instance lives as
/// long as the map.
///
/// Two behaviours, per the owner's brief:
///
///  * **Stationary coincident vehicles are fanned out** (several at a stop or
///    terminus read as several, F4). Their positions don't move, so the fan is
///    stable: no hold or debounce needed.
///  * **Moving vehicles are never displaced.** Two that cross (oncoming lanes,
///    an intersection) simply pass over each other; the overlapping ones fade
///    slightly so the overlap reads as two, not one. No sideways jumps.
///
/// Fan offsets and crossing opacity are eased while frames are being produced
/// and snapped on a one-off write at rest, so nothing is left half-arranged
/// and idle stays at zero frames.
class VehicleArranger {
  /// Applied fan offset per key (dLat, dLon), only for stationary coincident
  /// vehicles.
  final Map<String, ll.LatLng> _offset = {};

  /// Eased crossing dim per key (a moving vehicle overlapping another).
  final Map<String, double> _crossOpacity = {};

  bool _fanAnimating = false;

  /// True while a fan is still forming, dissolving or re-fanning: the caller
  /// keeps the frame driver running until it settles, even when no vehicle is
  /// playing (a choral HOLD parks every marker), so offsets ease instead of
  /// snapping.
  bool get fanAnimating => _fanAnimating;

  /// Arrange [objects] for camera [zoom]. [driverRunning] says whether frames
  /// are being produced (then changes ease, otherwise they snap).
  /// [refLatitude] sets the metres-per-pixel scale.
  List<MovingObject> arrange(
    List<MovingObject> objects,
    double zoom, {
    required bool driverRunning,
    required double refLatitude,
  }) {
    // Far zoom shows plain dots (below the detail threshold): don't fan or
    // cross-fade there. The cell grid is coarse in metres when zoomed out, so
    // membership churns as the camera moves — that churn read as jitter on the
    // overview. Dots overlapping is fine; render true positions, state cleared.
    if (objects.isEmpty || zoom < kMovingObjectDetailZoom) {
      _offset.clear();
      _crossOpacity.clear();
      _fanAnimating = false;
      return objects;
    }
    final metersPerPixel =
        156543.03392 *
        math.cos(refLatitude * math.pi / 180) /
        math.pow(2, zoom);
    final radiusM = 16.0 * metersPerPixel; // fan radius, constant on screen

    // Overlap thresholds, in screen pixels so they mean the same at any zoom —
    // and hysteretic. With one threshold, a pair sitting right at it fans out,
    // collapses, fans out again. So a fan only *forms* on a strong overlap
    // ([enterM], markers clearly on top of each other) and only *collapses*
    // once they are comfortably apart ([exitM]); in between, whatever the fan is
    // already doing wins.
    final enterM = 24.0 * metersPerPixel;
    final exitM = 40.0 * metersPerPixel;
    String cellOf(ll.LatLng p, double m) {
      final lat = m / 111320.0;
      final lon = m / (111320.0 * math.cos(p.latitude * math.pi / 180));
      return '${(p.latitude / lat).floor()}:${(p.longitude / lon).floor()}';
    }

    // --- Pass 1: fan out stationary coincident vehicles ---------------------
    // Consider ONLY the stationary ones, so a moving vehicle passing through a
    // parked cluster's cell can't collapse the fan. `moving` counts a stop dwell
    // as motion (TimedTrajectory.isPlaying): a bus pausing three seconds is
    // mid-journey, and fanning it out on arrival only to snap it back as it
    // pulls away would be a shove at every stop.
    final crowdedEnter = <String, int>{};
    final byExitCell = <String, List<int>>{};
    for (var i = 0; i < objects.length; i++) {
      if (objects[i].moving) continue;
      final p = objects[i].position;
      crowdedEnter.update(cellOf(p, enterM), (v) => v + 1, ifAbsent: () => 1);
      byExitCell.putIfAbsent(cellOf(p, exitM), () => []).add(i);
    }
    final offsetTarget = <String, ll.LatLng>{}; // dLat,dLon per key
    for (final group in byExitCell.values) {
      // Who in this loose group actually earns a fan: anyone strongly overlapped
      // right now, plus anyone already fanned (that's the hysteresis — they hold
      // their place until the whole group thins out).
      final members = [
        for (final i in group)
          if ((crowdedEnter[cellOf(objects[i].position, enterM)] ?? 0) >= 2 ||
              _offset.containsKey(objects[i].key))
            i,
      ];
      if (members.length < 2) continue;
      members.sort((a, b) => objects[a].key.compareTo(objects[b].key));
      for (var r = 0; r < members.length; r++) {
        final o = objects[members[r]];
        final angle = 2 * math.pi * r / members.length;
        offsetTarget[o.key] = ll.LatLng(
          radiusM * math.sin(angle) / 111320.0,
          radiusM *
              math.cos(angle) /
              (111320.0 * math.cos(o.position.latitude * math.pi / 180)),
        );
      }
    }

    // Is the fan still in transit — any key's offset not yet at its target?
    // (Forming, dissolving, or re-fanning.) If so while the driver is stopped —
    // a choral HOLD parks every marker, so nothing is "playing" to keep it alive
    // — kick the driver so the offsets EASE instead of snapping (a sideways shove
    // reads as a glitch). It self-stops once [_fanAnimating] clears below.
    var changing = false;
    for (final o in objects) {
      final tgt = offsetTarget[o.key] ?? const ll.LatLng(0, 0);
      final cur = _offset[o.key] ?? const ll.LatLng(0, 0);
      if ((tgt.latitude - cur.latitude).abs() > 1e-7 ||
          (tgt.longitude - cur.longitude).abs() > 1e-7) {
        changing = true;
        break;
      }
    }
    _fanAnimating = changing;
    final ease = (driverRunning || changing) ? 0.3 : 1.0;

    // Ease each key's applied offset toward its target (zero if not in a
    // stationary cluster) and compute placed positions.
    final placedPos = <ll.LatLng>[];
    for (final o in objects) {
      final target = offsetTarget[o.key] ?? const ll.LatLng(0, 0);
      final cur = _offset[o.key] ?? const ll.LatLng(0, 0);
      final applied = ll.LatLng(
        cur.latitude + (target.latitude - cur.latitude) * ease,
        cur.longitude + (target.longitude - cur.longitude) * ease,
      );
      if (applied.latitude.abs() < 1e-7 && applied.longitude.abs() < 1e-7) {
        _offset.remove(o.key);
        placedPos.add(o.position);
      } else {
        _offset[o.key] = applied;
        placedPos.add(
          ll.LatLng(
            o.position.latitude + applied.latitude,
            o.position.longitude + applied.longitude,
          ),
        );
      }
    }

    // --- Pass 2: cross-fade moving vehicles that overlap --------------------
    // Count occupancy of each cell at the placed positions; a MOVING vehicle
    // sharing a cell with anything else is "crossing" and dims a little. Its own
    // threshold (~a marker's width): the fan's enter/exit pair above is about
    // whether to *move* a marker, which needs the hysteresis; a fade is
    // continuous and eased, so a single threshold can't flicker.
    final overlapM = 30.0 * metersPerPixel;
    final cellCount = <String, int>{};
    for (final p in placedPos) {
      cellCount.update(cellOf(p, overlapM), (v) => v + 1, ifAbsent: () => 1);
    }
    const crossOpacity = 0.7;
    final present = <String>{};
    final result = <MovingObject>[];
    for (var i = 0; i < objects.length; i++) {
      final o = objects[i];
      present.add(o.key);
      final crossing =
          o.moving && (cellCount[cellOf(placedPos[i], overlapM)] ?? 0) > 1;
      final targetOpacity = crossing ? crossOpacity : 1.0;
      final curOpacity = _crossOpacity[o.key] ?? 1.0;
      final appliedOpacity = curOpacity + (targetOpacity - curOpacity) * ease;
      if ((appliedOpacity - 1.0).abs() < 0.02) {
        _crossOpacity.remove(o.key);
      } else {
        _crossOpacity[o.key] = appliedOpacity;
      }
      result.add(
        MovingObject(
          key: o.key,
          position: placedPos[i],
          kind: o.kind,
          label: o.label,
          heading: o.heading,
          selected: o.selected,
          stuck: o.stuck,
          // Combine the grace/scheduled fade with the crossing dim.
          opacity: o.opacity * appliedOpacity,
          moving: o.moving,
          source: o.source,
        ),
      );
    }
    _offset.removeWhere((k, _) => !present.contains(k));
    _crossOpacity.removeWhere((k, _) => !present.contains(k));
    return result;
  }
}
