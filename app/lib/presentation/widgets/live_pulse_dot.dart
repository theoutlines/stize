import 'package:flutter/material.dart';

import '../../core/design/stize_tokens.dart';

/// The small white dot beside a live vehicle's position: it breathes while the
/// vehicle moves. Every dot on screen shares one phase (derived from the wall
/// clock), so a board full of cards pulses as one, not as a scatter of
/// out-of-sync blinks. Opacity only; still under reduce-motion.
class LivePulseDot extends StatefulWidget {
  const LivePulseDot({super.key, required this.color, this.size = 6});

  final Color color;
  final double size;

  /// One breath: fade down and back up.
  static const Duration period = Duration(milliseconds: 1600);

  /// Off in widget tests (an endless animation never lets a test settle);
  /// see test/flutter_test_config.dart.
  static bool animate = true;

  @override
  State<LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: LivePulseDot.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still =
        !LivePulseDot.animate ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (still) {
      _ctl.stop();
      _ctl.value = 0;
    } else if (!_ctl.isAnimating) {
      // Start at the shared phase so every dot is in step.
      final ms = DateTime.now().millisecondsSinceEpoch;
      _ctl.value = (ms % LivePulseDot.period.inMilliseconds) /
          LivePulseDot.period.inMilliseconds;
      _ctl.repeat();
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    return AnimatedBuilder(
      animation: _ctl,
      child: dot,
      builder: (context, child) {
        // 1 → 0.35 → 1, eased.
        final t = StizeMotion.inOut.transform(
          _ctl.value < 0.5 ? _ctl.value * 2 : (1 - _ctl.value) * 2,
        );
        return Opacity(opacity: 1 - 0.65 * t, child: child);
      },
    );
  }
}
