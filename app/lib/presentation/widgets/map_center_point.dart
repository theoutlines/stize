import 'package:flutter/material.dart';

import '../../core/design/stize_tokens.dart';
import '../../core/map_support.dart';

/// Your own dot, taken off its GPS fix and set on the map's visible centre
/// (owner, 2026-11-25, after Transit): drag the map and the dot lifts and goes
/// half transparent; let go and it drops back with a bounce, and Nearby
/// recomputes around that point. The locate button brings it home.
class MapCenterPoint extends StatelessWidget {
  const MapCenterPoint({super.key, required this.lifted, required this.drop});

  /// The map is being dragged.
  final bool lifted;

  /// Bumped on every drop: replays the bounce.
  final int drop;

  static const double _lift = 14;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final dot = const MeLocationDot();
    final shadow = Container(
      width: 12,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
      ),
    );
    if (lifted) {
      return SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(top: 22, child: shadow),
            Transform.translate(
              offset: const Offset(0, -_lift),
              child: Opacity(opacity: 0.6, child: dot),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      width: 40,
      height: 40,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(drop),
        tween: Tween(begin: still ? 0 : 1, end: 0),
        duration: still ? Duration.zero : StizeMotion.medium,
        curve: Curves.bounceOut,
        builder: (context, t, child) => Transform.translate(
          offset: Offset(0, -_lift * t),
          child: Opacity(opacity: 1 - 0.4 * t, child: child),
        ),
        child: Center(child: dot),
      ),
    );
  }
}
