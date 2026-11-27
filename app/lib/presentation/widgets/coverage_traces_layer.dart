import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
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
/// every route as a thin thread, light adding up where routes share a
/// street (additive inside our own layer: blue on blue runs to cyan and
/// white, tram over bus to magenta; on the light map plain ink). Two wider,
/// fainter passes of the same threads make the glow. Widths are fixed on
/// screen, so a junction of thirty routes is brighter, never wider.
///
/// Cheap on every device: the threads are recorded once as a vector picture
/// (again when the zoom moves a quarter step, for the widths, at most every
/// [_rerecordGap] while the zoom keeps moving), and each frame just places
/// that picture with the camera. No images, no blur. Each route is thinned
/// to the points that matter at the current whole zoom (half a pixel), so a
/// phone strokes a few thousand points per frame, not all ~50 000.
///
/// Lives among the map's widget children, so it rebuilds with the camera.
class CoverageTracesLayer extends ConsumerStatefulWidget {
  const CoverageTracesLayer({super.key});

  @override
  ConsumerState<CoverageTracesLayer> createState() => _CoverageTracesState();
}

/// Where the local origin lands on screen, and how the local units scale and
/// turn: the whole map-to-screen mapping (Coverage has no pitch).
typedef _Affine = ({Offset origin, double scale, double angle});

/// While the zoom keeps moving, a new picture at most this often; between
/// recordings the last one is scaled with the camera.
const _rerecordGap = Duration(milliseconds: 250);

class _CoverageTracesState extends ConsumerState<CoverageTracesLayer> {
  ui.Picture? _picture;
  Object? _key; // traces, filters, theme, zoom step the picture was made for
  Object? _baseKey; // the same without the zoom step
  DateTime _recordedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _catchUp;

  /// Thinned paths per whole zoom level, for one trace set.
  CoverageTraces? _pathsOf;
  final _paths = <int, List<ui.Path>>{};

  @override
  void dispose() {
    _catchUp?.cancel();
    _picture?.dispose();
    super.dispose();
  }

  List<ui.Path> _pathsAt(CoverageTraces t, int zoom, double tolerance) {
    if (!identical(_pathsOf, t)) {
      _paths.clear();
      _pathsOf = t;
    }
    return _paths[zoom] ??= [
      for (final tr in t.traces)
        () {
          final p = tr.simplified(tolerance);
          return ui.Path()..addPolygon([
            for (var i = 0; i + 1 < p.length; i += 2) Offset(p[i], p[i + 1]),
          ], false);
        }(),
    ];
  }

  _Affine? _affine(MapController c) {
    final o = CoverageTraces.origin;
    final (lon0, lat0) = CoverageTraces.lonLatOf(o.$1, o.$2);
    const dx = 1e-4; // world units, ~1 km at Belgrade
    final (lon1, lat1) = CoverageTraces.lonLatOf(o.$1 + dx, o.$2);
    final s = c.toScreenLocations([
      Geographic(lon: lon0, lat: lat0),
      Geographic(lon: lon1, lat: lat1),
    ]);
    final v = s[1] - s[0];
    if (v.distance == 0) return null;
    return (
      origin: s[0],
      scale: v.distance / (dx * CoverageTraces.unit),
      angle: math.atan2(v.dy, v.dx),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = MapController.maybeOf(context);
    final camera = MapCamera.maybeOf(context);
    final traces = ref.watch(coverageTracesProvider).valueOrNull;
    final types = ref.watch(coverageTypesProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (controller == null || camera == null || traces == null) {
      return const SizedBox.shrink();
    }
    final at = _affine(controller);
    if (at == null) return const SizedBox.shrink();
    // Widths live in local units, so a new picture each quarter zoom step.
    final step = (camera.zoom * 4).round() / 4;
    final base = (traces, Object.hashAllUnordered(types), dark);
    final key = (base, step);
    final now = DateTime.now();
    final sinceLast = now.difference(_recordedAt);
    // Only the zoom moved, and a picture was made a moment ago: keep scaling
    // that one and catch up once the zoom has been still for a moment.
    final waitForZoom =
        _picture != null && _baseKey == base && sinceLast < _rerecordGap;
    if (_key != key && waitForZoom) {
      _catchUp?.cancel();
      _catchUp = Timer(_rerecordGap - sinceLast, () {
        if (mounted) setState(() {});
      });
    } else if (_key != key) {
      _picture?.dispose();
      // Local units per screen pixel at that step.
      final perPx = 1 / (at.scale * math.pow(2, step - camera.zoom));
      final whole = step.floor();
      final paths = _pathsAt(
        traces,
        whole,
        0.5 * perPx * math.pow(2, step - whole), // half a pixel at `whole`
      );
      _picture = _record(traces, paths, types, dark, step, perPx);
      _key = key;
      _baseKey = base;
      _recordedAt = now;
    }
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _Placer(picture: _picture!, at: at),
      ),
    );
  }
}

/// Places the recorded picture with the camera.
class _Placer extends CustomPainter {
  _Placer({required this.picture, required this.at});

  final ui.Picture picture;
  final _Affine at;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(at.origin.dx, at.origin.dy);
    canvas.rotate(at.angle);
    canvas.scale(at.scale);
    canvas.drawPicture(picture);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Placer old) => old.picture != picture || old.at != at;
}

/// Per type: the thread colour on the dark map, then on the light map.
const _colors = <String, (Color, Color)>{
  'bus': (Color(0xFF2D7FF0), Color(0xFF1E5FD0)),
  'trolleybus': (Color(0xFFFF8A1A), Color(0xFFE07000)),
  'tram': (Color(0xFFFF3B3B), Color(0xFFD6282B)),
};

/// Bottom first: bus, the widest network, under trolleybus and tram.
const _order = ['bus', 'trolleybus', 'tram'];

/// Records the threads in local units; [perPx] converts screen px widths.
ui.Picture _record(
  CoverageTraces traces,
  List<ui.Path> paths,
  Set<String> types,
  bool dark,
  double zoom,
  double perPx,
) {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final t = ((zoom - 11) / 6).clamp(0.0, 1.0);
  final core = ui.lerpDouble(1.0, 2.6, t)!; // screen px
  // Fainter at the city view, where many more threads overlap per pixel.
  final fade = ui.lerpDouble(0.4, 1, ((zoom - 11) / 4).clamp(0.0, 1.0))!;
  double alpha(int trips) =>
      (0.08 + 0.42 * math.min(1.0, math.sqrt(trips / 260))) * fade;
  // Light adds up on the dark map; on the light map ink lays over ink.
  final blend = dark ? BlendMode.plus : BlendMode.srcOver;
  // Glow, then the thread: wide and faint passes under the crisp one.
  final passes = dark
      ? const [(6.0, 0.06), (3.0, 0.14), (1.0, 1.0)]
      : const [(4.0, 0.05), (1.0, 1.0)];

  // One layer of our own, so `plus` adds threads to threads, never to the map.
  // On the web the map is a separate page element under a transparent Flutter
  // canvas, so the threads already add only to each other: skip the offscreen
  // layer (a full-screen texture per frame, too much for phones).
  final ownLayer = !kIsWeb;
  if (ownLayer) canvas.saveLayer(null, Paint());
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..blendMode = blend;
  for (final (k, a) in passes) {
    paint.strokeWidth = core * k * perPx;
    for (final type in _order) {
      if (types.isNotEmpty && !types.contains(type)) continue;
      final (onDark, onLight) = _colors[type]!;
      final base = dark ? onDark : onLight;
      for (var i = 0; i < traces.traces.length; i++) {
        final tr = traces.traces[i];
        if (tr.type != type) continue;
        paint.color = base.withValues(alpha: alpha(tr.trips) * a);
        canvas.drawPath(paths[i], paint);
      }
    }
  }
  if (ownLayer) canvas.restore();
  return rec.endRecording();
}
