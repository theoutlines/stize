import 'package:maplibre/maplibre.dart' show CameraChangeReason;

import 'moving_object_layer.dart';

/// Pure decisions for the map's follow-a-vehicle mode, kept out of the widget so
/// they can be unit-tested without a live map.

/// Whether a camera move-start event should break follow.
///
/// A move the app itself just issued ([selfMove]) NEVER breaks follow — even if
/// the platform reports it as `apiGesture` — so the per-frame follow pan can't
/// cancel its own follow (the classic self-cancelling-follow bug). Only a
/// genuine user gesture, while following and not mid-self-move, breaks it.
bool shouldBreakFollow({
  required bool following,
  required bool selfMove,
  required CameraChangeReason reason,
}) {
  if (!following || selfMove) return false;
  return reason == CameraChangeReason.apiGesture;
}

/// The layer id the focused-line view must be inserted *below* so its route +
/// stops render under every moving-object symbol (never over the followed coin).
/// The badge is the lowest of the vehicle layers, so below-badge is below all of
/// them. Null when the vehicle layers aren't up yet — the focus then goes on top
/// of the base map, which is still correct.
String? focusInsertBelowLayerId({required bool vehicleLayersAdded}) =>
    vehicleLayersAdded ? movingObjectsLayersBottomToTop.first : null;

/// The pace of follow mode: when the camera may start tracking, and how often
/// it moves.
///
/// Follow engages once the entry fly-to has settled ([engage]); if that
/// flight's future never completes (on web an interrupted flight never
/// resolves), it engages anyway after [engageFallback]: the map must never
/// stop tracking. Once engaged, the camera re-centres at most every
/// [interval] (~15 fps): panning the whole map on every frame made pins and
/// street labels jitter against the moving camera.
class FollowPacer {
  FollowPacer({
    this.engageFallback = const Duration(milliseconds: 1200),
    this.interval = const Duration(milliseconds: 66),
  });

  final Duration engageFallback;
  final Duration interval;

  bool _engaged = false;
  DateTime? _startedAt;
  DateTime? _lastMoveAt;

  bool get engaged => _engaged;

  /// Follow (re)starts at [now]. With [afterFlight] it waits for [engage] (or
  /// the fallback); otherwise it tracks at once.
  void start(DateTime now, {required bool afterFlight}) {
    _startedAt = now;
    _lastMoveAt = null;
    _engaged = !afterFlight;
  }

  /// The entry flight settled.
  void engage() => _engaged = true;

  /// Follow stopped.
  void stop() => _engaged = false;

  /// Engaged by now? Engages on the fallback when the flight never reported.
  bool readyAt(DateTime now) {
    if (_engaged) return true;
    final started = _startedAt;
    if (started == null || now.difference(started) < engageFallback) {
      return false;
    }
    return _engaged = true;
  }

  /// Whether the camera should move on this tick; records the move.
  bool moveDueAt(DateTime now) {
    final last = _lastMoveAt;
    if (last != null && now.difference(last) < interval) return false;
    _lastMoveAt = now;
    return true;
  }
}
