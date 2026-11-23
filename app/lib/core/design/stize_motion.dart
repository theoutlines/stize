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
}
