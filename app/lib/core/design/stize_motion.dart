import 'package:flutter/animation.dart';

/// Motion tokens from the system's motion library (transitions.dev scale).
/// Opens carry the distance; closes are quicker and quieter.
abstract final class StizeMotion {
  static const Duration stagger = Duration(milliseconds: 40);
  static const Duration micro = Duration(milliseconds: 80);

  /// Close of a menu/modal, a text or number swap.
  static const Duration quick = Duration(milliseconds: 150);

  /// Open of a menu/modal, an icon swap, a list item entering.
  static const Duration fast = Duration(milliseconds: 250);

  /// A panel or sheet closing.
  static const Duration medium = Duration(milliseconds: 350);

  /// A panel or sheet opening.
  static const Duration slow = Duration(milliseconds: 400);

  /// Surface motion: open/close, slide, resize, position change.
  static const Curve smoothOut = Cubic(0.22, 1, 0.36, 1);

  /// Text and icon swaps.
  static const Curve inOut = Curves.easeInOut;

  /// Travel of an in-place text swap.
  static const double distanceMicro = 4;

  /// Pre-scale of a dropdown / popover opening.
  static const double scaleDropdown = 0.97;

  /// Close of a surface that opens on [fast]: its reverse curve finishes in the
  /// first 60% of the run, so a 250 ms open closes in 150 ms ([quick]).
  static const Curve closeQuick = Interval(0.4, 1, curve: smoothOut);

  /// The map camera easing to a stop, a route or me. Map motion is longer
  /// than UI motion: the eye has to follow a place, not a surface.
  static const Duration camera = Duration(milliseconds: 700);

  /// The longest a web camera flight may take (MapLibre web flies by speed).
  static const Duration cameraMax = Duration(milliseconds: 800);

  /// One beat of a looping signal (the live pulse on a vehicle marker).
  static const Duration loop = Duration(milliseconds: 1500);

  /// The desktop panel sliding to its edge tab and back: short and plain by
  /// the owner's call (decision A#2, ~200 ms, no physics), quicker than [slow]
  /// because it is a reveal the user asked for, not a surface opening.
  static const Duration panelSlide = Duration(milliseconds: 200);
}
