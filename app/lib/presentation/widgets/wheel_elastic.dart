import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/design/stize_tokens.dart';

/// The rubber band for a mouse wheel or trackpad (owner, 2026-11-25). A drag
/// bounces through [BouncingScrollPhysics], but on the web a trackpad swipe
/// arrives as scroll signals that simply stop at the edge. Scrolling past the
/// top or bottom of [child]'s list pulls the content a little (with
/// resistance) and springs it back once the gesture pauses.
class WheelElastic extends StatefulWidget {
  const WheelElastic({super.key, required this.child});

  final Widget child;

  /// The farthest the content is pulled.
  static const double maxPull = 56;

  @override
  State<WheelElastic> createState() => _WheelElasticState();
}

class _WheelElasticState extends State<WheelElastic>
    with SingleTickerProviderStateMixin {
  ScrollMetrics? _metrics;
  double _pull = 0;
  Timer? _rest;
  // Created in initState, not lazily: a lazy controller first touched in
  // dispose() looks up TickerMode on a deactivated element (CI failure).
  late final AnimationController _back;
  late final Animation<double> _curve;
  double _from = 0;

  @override
  void initState() {
    super.initState();
    _back = AnimationController(vsync: this, duration: StizeMotion.medium)
      ..addListener(() => setState(() => _pull = _from * (1 - _curve.value)));
    _curve = CurvedAnimation(parent: _back, curve: StizeMotion.smoothOut);
  }

  @override
  void dispose() {
    _rest?.cancel();
    _back.dispose();
    super.dispose();
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final m = _metrics;
    final dy = e.scrollDelta.dy;
    if (dy == 0 || dy.abs() < e.scrollDelta.dx.abs()) return;
    final atTop = m == null || m.pixels <= m.minScrollExtent + 0.5;
    final atBottom = m == null || m.pixels >= m.maxScrollExtent - 0.5;
    if (!((dy < 0 && atTop) || (dy > 0 && atBottom))) return;
    _back.stop();
    // Resistance grows as the pull gets longer.
    final room = 1 - (_pull.abs() / WheelElastic.maxPull);
    setState(() {
      _pull = (_pull - dy * 0.35 * room.clamp(0.0, 1.0)).clamp(
        -WheelElastic.maxPull,
        WheelElastic.maxPull,
      );
    });
    _rest?.cancel();
    _rest = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _pull == 0) return;
      _from = _pull;
      _back.forward(from: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        if (n.depth == 0) _metrics = n.metrics;
        return false;
      },
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (n) {
          if (n.depth == 0) _metrics = n.metrics;
          return false;
        },
        child: Listener(
          onPointerSignal: _onSignal,
          child: Transform.translate(
            offset: Offset(0, _pull),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
