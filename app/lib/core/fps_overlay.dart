import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'api_config.dart';

/// Compile-time gate for the on-screen FPS read-out. Lives beside
/// `kMapRenderingEnabled` in spirit: OFF in a normal build, flipped on with
/// `--dart-define=SHOW_FPS_OVERLAY=true`. Independent of the runtime URL toggle
/// below so it can also be forced on for a local run.
const bool kShowFpsOverlay =
    bool.fromEnvironment('SHOW_FPS_OVERLAY', defaultValue: false);

/// Whether the FPS overlay should be shown for this session.
///
/// On **production** builds it is only ever on via the compile-time flag (never
/// via a URL param), so a prod visitor can't turn it on. On a **staging /
/// preview** build the owner can flip it on with no terminal by appending
/// `?fps=1` to the preview URL — handy for an on-device (iOS Safari) perf check
/// where desktop numbers don't transfer.
bool fpsOverlayEnabled() {
  if (kShowFpsOverlay) return true;
  if (appEnvironment == 'production') return false;
  if (kIsWeb && Uri.base.queryParameters['fps'] == '1') return true;
  return false;
}

/// A tiny frame-rate meter for the corner of the map — a diagnostic for
/// on-device perf checks, not a shipped UI. Shown only when [fpsOverlayEnabled].
///
/// Measurement is passive and self-quiescing: it reads Flutter's own
/// [FrameTiming]s (no external deps) and folds them into a reading at most every
/// 0.5s, updating *from inside the timings callback* — so it rides frames the
/// app already produces and drives no ticker/timer of its own. When the app is
/// idle no frames arrive, so the meter neither updates nor keeps the engine
/// awake (it measures the app, not itself; "idle = zero frames" holds even with
/// the overlay shown). When disabled it isn't built at all.
class FpsOverlay extends StatefulWidget {
  const FpsOverlay({super.key});

  @override
  State<FpsOverlay> createState() => _FpsOverlayState();
}

class _FpsOverlayState extends State<FpsOverlay> {
  final ValueNotifier<_Reading> _reading = ValueNotifier(const _Reading(0, 0));
  final Stopwatch _window = Stopwatch();
  int _frames = 0;
  int _totalUs = 0;

  void _onTimings(List<FrameTiming> timings) {
    if (!_window.isRunning) _window.start();
    for (final t in timings) {
      _frames++;
      _totalUs += t.totalSpan.inMicroseconds;
    }
    final ms = _window.elapsedMilliseconds;
    if (ms < 500) return;
    // Fold the window into a reading and reset. This update schedules one frame
    // (the overlay text), but the throttle means at most ~2 such frames a second
    // — negligible during real animation, and none at all when the app is idle
    // (this callback only fires when the app itself produced a frame).
    final fps = _frames * 1000.0 / ms;
    final avgMs = _frames == 0 ? 0.0 : (_totalUs / _frames) / 1000.0;
    _reading.value = _Reading(fps, avgMs);
    _frames = 0;
    _totalUs = 0;
    _window
      ..reset()
      ..start();
  }

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _reading.dispose();
    super.dispose();
  }

  Color _color(double fps) {
    if (fps >= 50) return const Color(0xFF37D67A); // green: smooth
    if (fps >= 30) return const Color(0xFFF5A623); // amber: watch
    return const Color(0xFFE8483E); // red: janky
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<_Reading>(
        valueListenable: _reading,
        builder: (context, r, _) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${r.fps.round()} fps · ${r.avgMs.toStringAsFixed(1)} ms',
              style: TextStyle(
                color: _color(r.fps),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Reading {
  const _Reading(this.fps, this.avgMs);
  final double fps;
  final double avgMs;
}
