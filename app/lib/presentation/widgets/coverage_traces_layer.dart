import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre/maplibre.dart';

import '../../core/coverage_traces.dart';
import '../providers/providers.dart';

/// Every city route for the Coverage map (backend `/api/v1/coverage/routes`),
/// fetched once when Coverage first opens.
final coverageTracesProvider = FutureProvider<CoverageTraces>((ref) async {
  final json = await ref
      .watch(apiClientProvider)
      .getJson('/api/v1/coverage/routes', {'rev': '1'});
  return CoverageTraces.fromJson(json);
});

/// The Coverage map drawn by the app itself, the same on web and native:
/// every route as a thin thread, with light adding up where routes share a
/// street. On the dark map the threads are light (additive: blue on blue
/// runs to cyan and white, red over blue to magenta); on the light map they
/// are ink (multiplied: overlaps deepen). A soft glow of the same threads
/// sits under them. Threads and glow have a fixed screen width, so a
/// junction of thirty routes is brighter, never wider.
///
/// Lives among the map's widget children, so it rebuilds with the camera.
class CoverageTracesLayer extends ConsumerWidget {
  const CoverageTracesLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = MapController.maybeOf(context);
    final camera = MapCamera.maybeOf(context);
    final traces = ref.watch(coverageTracesProvider).valueOrNull;
    if (controller == null || camera == null || traces == null) {
      return const SizedBox.shrink();
    }
    // Where the local origin and a point one km east of it land on screen:
    // enough to place, scale and turn the whole picture (no pitch here).
    final o = CoverageTraces.origin;
    final (lon0, lat0) = CoverageTraces.lonLatOf(o.$1, o.$2);
    const dx = 1e-4; // world units, ~1 km at Belgrade
    final (lon1, lat1) = CoverageTraces.lonLatOf(o.$1 + dx, o.$2);
    final s = controller.toScreenLocations([
      Geographic(lon: lon0, lat: lat0),
      Geographic(lon: lon1, lat: lat1),
    ]);
    final v = s[1] - s[0];
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _TracesPainter(
          traces: traces,
          origin: s[0],
          scale: v.distance / (dx * CoverageTraces.unit),
          angle: math.atan2(v.dy, v.dx),
          zoom: camera.zoom,
          types: ref.watch(coverageTypesProvider),
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    );
  }
}

/// Per type: the thread colour on the dark map, then on the light map.
const _colors = <String, (Color, Color)>{
  'bus': (Color(0xFF2D7FF0), Color(0xFF1E5FD0)),
  'trolleybus': (Color(0xFFFF8A1A), Color(0xFFE07000)),
  'tram': (Color(0xFFFF3B3B), Color(0xFFD6282B)),
};

/// Bottom first: bus, the widest network, under trolleybus and tram.
const _order = ['bus', 'trolleybus', 'tram'];

class _TracesPainter extends CustomPainter {
  _TracesPainter({
    required this.traces,
    required this.origin,
    required this.scale,
    required this.angle,
    required this.zoom,
    required this.types,
    required this.dark,
  });

  final CoverageTraces traces;
  final Offset origin;
  final double scale;
  final double angle;
  final double zoom;
  final Set<String> types;
  final bool dark;

  /// Paths are built once per trace set and reused for every frame.
  static final _paths = Expando<List<ui.Path>>();

  List<ui.Path> _pathsFor(CoverageTraces t) => _paths[t] ??= [
    for (final tr in t.traces)
      ui.Path()..addPolygon([
        for (var i = 0; i + 1 < tr.points.length; i += 2)
          Offset(tr.points[i], tr.points[i + 1]),
      ], false),
  ];

  /// Thread opacity from the route's own trips (busiest single ~260 a day).
  /// Fainter at the city view, where many more threads overlap per pixel.
  double _alpha(int trips) =>
      (0.08 + 0.42 * math.min(1.0, math.sqrt(trips / 260))) *
      ui.lerpDouble(0.4, 1, ((zoom - 11) / 4).clamp(0.0, 1.0))!;

  @override
  void paint(Canvas canvas, Size size) {
    final paths = _pathsFor(traces);
    final bounds = Offset.zero & size;
    final t = ((zoom - 11) / 6).clamp(0.0, 1.0);
    final core = ui.lerpDouble(1.0, 2.6, t)!; // screen px
    final glow = ui.lerpDouble(3, 10, t)!; // blur sigma, screen px

    void drawThreads(double widthPx, double alphaK) {
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.rotate(angle);
      canvas.scale(scale);
      for (final type in _order) {
        if (types.isNotEmpty && !types.contains(type)) continue;
        final (onDark, onLight) = _colors[type]!;
        final base = dark ? onDark : onLight;
        for (var i = 0; i < traces.traces.length; i++) {
          final tr = traces.traces[i];
          if (tr.type != type) continue;
          canvas.drawPath(
            paths[i],
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = widthPx / scale
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..isAntiAlias = true
              ..blendMode = dark ? BlendMode.plus : BlendMode.multiply
              ..color = base.withValues(alpha: _alpha(tr.trips) * alphaK),
          );
        }
      }
      canvas.restore();
    }

    // The whole picture is one layer laid over the map: added as light on
    // the dark map, multiplied as ink on the light one.
    canvas.saveLayer(
      bounds,
      Paint()..blendMode = dark ? BlendMode.srcOver : BlendMode.multiply,
    );
    if (!dark) canvas.drawPaint(Paint()..color = const Color(0xFFFFFFFF));
    // Glow: the same threads, wider and blurred.
    canvas.saveLayer(
      bounds,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: glow, sigmaY: glow)
        ..blendMode = dark ? BlendMode.plus : BlendMode.multiply,
    );
    if (!dark) canvas.drawPaint(Paint()..color = const Color(0xFFFFFFFF));
    drawThreads(core * 3, dark ? 0.6 : 0.4);
    canvas.restore();
    drawThreads(core, 1);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TracesPainter old) =>
      old.origin != origin ||
      old.scale != scale ||
      old.angle != angle ||
      old.traces != traces ||
      old.dark != dark ||
      !setEquals(old.types, types);
}
