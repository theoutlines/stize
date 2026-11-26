import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Overscroll and refresh tokens (design system: StretchList, owner
/// 2026-11-26). One feel for every list and sheet, touch and trackpad alike.
abstract final class StizeOverscroll {
  /// Touch pull past an end: share of the finger's travel the list follows at
  /// the edge, falling with the square of how far it is already pulled.
  /// Flutter's iOS default is 0.52; ours is stiffer.
  static const double touchFriction = 0.28;

  /// Trackpad / wheel pull past an end: share of each scroll step, falling
  /// with the power 1.5 of how far it is already pulled (squared made the
  /// refresh trigger unreachable, owner 2026-11-26).
  static const double wheelGain = 0.3;

  /// Trackpad / wheel: the farthest a pull can stretch, in logical pixels.
  /// Well past [refreshTrigger], so a deliberate pull refreshes.
  static const double wheelReach = 120;

  /// Pull to refresh: stretch at which letting go refreshes.
  static const double refreshTrigger = 64;

  /// Pull to refresh: the band held open while the list refreshes.
  static const double refreshHold = 52;

  /// Pull to refresh: the spinner shows at least this long, so a fast fetch
  /// still reads as a refresh.
  static const Duration refreshMinHold = Duration(milliseconds: 600);
}

/// Bouncing with the system's stiffer resistance.
class StizeBouncePhysics extends BouncingScrollPhysics {
  const StizeBouncePhysics({super.parent});

  @override
  StizeBouncePhysics applyTo(ScrollPhysics? ancestor) =>
      StizeBouncePhysics(parent: buildParent(ancestor));

  @override
  double frictionFactor(double overscrollFraction) =>
      StizeOverscroll.touchFriction * math.pow(1 - overscrollFraction, 2);
}

/// Every scrollable in the app bounces the same way (one list feel on every
/// platform, owner 2026-11-26), with no Material glow on top.
class StizeScrollBehavior extends MaterialScrollBehavior {
  const StizeScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const StizeBouncePhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
