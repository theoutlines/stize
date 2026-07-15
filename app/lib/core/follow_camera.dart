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
