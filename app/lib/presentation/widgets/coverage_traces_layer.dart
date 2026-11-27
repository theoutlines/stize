import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
/// white, tram over bus to magenta; on the light map plain ink). A soft glow
/// of the same threads sits under them. Threads and glow keep a fixed screen
/// width, so a junction of thirty routes is brighter, never wider.
///
/// Drawing every route is too heavy for each frame of a gesture, so the
/// picture is rendered once into an image when the camera settles, and while
/// the map moves that image is only moved, scaled and turned with it.
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

class _CoverageTracesState extends ConsumerState<CoverageTracesLayer> {
  ui.Image? _image;
  _Affine? _imageAt; // the camera the image was drawn for
  double _imageRatio = 1;
  Timer? _settle;
  Object? _key; // what the image shows: traces, types, theme, size
  int _gen = 0;
  bool _rendering = false;

  @override
  void dispose() {
    _settle?.cancel();
    _image?.dispose();
    super.dispose();
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

  /// Renders the picture for [at] into an image, a margin wider than the
  /// screen so a pan shows no empty edge before the next render.
  Future<void> _render({
    required CoverageTraces traces,
    required _Affine at,
    required double zoom,
    required Size size,
    required Set<String> types,
    required bool dark,
    required double ratio,
    required Object key,
  }) async {
    final gen = ++_gen;
    _rendering = true;
    final margin = Offset(size.width * _margin, size.height * _margin);
    final full = Size(size.width + margin.dx * 2, size.height + margin.dy * 2);
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.scale(ratio);
    canvas.translate(margin.dx, margin.dy);
    _paintTraces(
      canvas,
      Offset(-margin.dx, -margin.dy) & full,
      traces,
      at,
      zoom,
      types,
      dark,
    );
    final pic = rec.endRecording();
    final img = await pic.toImage(
      (full.width * ratio).ceil(),
      (full.height * ratio).ceil(),
    );
    pic.dispose();
    if (gen == _gen) _rendering = false;
    if (!mounted || gen != _gen) {
      img.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = img;
      _imageAt = at;
      _imageRatio = ratio;
      _key = key;
    });
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
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          final ratio = math.min(MediaQuery.devicePixelRatioOf(context), 2.0);
          final key = (traces, Object.hashAllUnordered(types), dark, size);
          // Re-render once the camera has rested, or at once when what the
          // picture shows changed (filters, theme) or nothing is drawn yet.
          _settle?.cancel();
          void go() => _render(
            traces: traces,
            at: at,
            zoom: camera.zoom,
            size: size,
            types: types,
            dark: dark,
            ratio: ratio,
            key: key,
          );
          if (_image == null || _key != key) {
            if (!_rendering) {
              _rendering = true;
              WidgetsBinding.instance.addPostFrameCallback((_) => go());
            }
          } else if (_imageAt != at) {
            _settle = Timer(const Duration(milliseconds: 180), go);
          }
          final img = _image;
          final was = _imageAt;
          if (img == null || was == null) return const SizedBox.expand();
          return CustomPaint(
            size: size,
            painter: _ImagePainter(
              image: img,
              ratio: _imageRatio,
              margin: Offset(size.width * _margin, size.height * _margin),
              from: was,
              to: at,
            ),
          );
        },
      ),
    );
  }
}

/// How far past each screen edge the image is drawn, as a share of the screen.
const _margin = 0.3;

/// Draws the last rendered image moved from the camera it was drawn for to
/// the current one: screen = to ∘ from⁻¹ (old screen).
class _ImagePainter extends CustomPainter {
  _ImagePainter({
    required this.image,
    required this.ratio,
    required this.margin,
    required this.from,
    required this.to,
  });

  final ui.Image image;
  final double ratio;
  final Offset margin;
  final _Affine from;
  final _Affine to;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(to.origin.dx, to.origin.dy);
    canvas.rotate(to.angle - from.angle);
    canvas.scale(to.scale / from.scale);
    canvas.translate(-from.origin.dx, -from.origin.dy);
    final w = image.width / ratio;
    final h = image.height / ratio;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(-margin.dx, -margin.dy, w, h),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ImagePainter old) =>
      old.image != image || old.from != from || old.to != to;
}

/// Per type: the thread colour on the dark map, then on the light map.
const _colors = <String, (Color, Color)>{
  'bus': (Color(0xFF2D7FF0), Color(0xFF1E5FD0)),
  'trolleybus': (Color(0xFFFF8A1A), Color(0xFFE07000)),
  'tram': (Color(0xFFFF3B3B), Color(0xFFD6282B)),
};

/// Bottom first: bus, the widest network, under trolleybus and tram.
const _order = ['bus', 'trolleybus', 'tram'];

/// Paths are built once per trace set and reused for every render.
final _paths = Expando<List<ui.Path>>();

List<ui.Path> _pathsFor(CoverageTraces t) => _paths[t] ??= [
  for (final tr in t.traces)
    ui.Path()..addPolygon([
      for (var i = 0; i + 1 < tr.points.length; i += 2)
        Offset(tr.points[i], tr.points[i + 1]),
    ], false),
];

/// Draws the threads and their glow for camera [at] into [bounds].
void _paintTraces(
  Canvas canvas,
  Rect bounds,
  CoverageTraces traces,
  ({Offset origin, double scale, double angle}) at,
  double zoom,
  Set<String> types,
  bool dark,
) {
  final paths = _pathsFor(traces);
  final t = ((zoom - 11) / 6).clamp(0.0, 1.0);
  final core = ui.lerpDouble(1.0, 2.6, t)!; // screen px
  final glow = ui.lerpDouble(3, 10, t)!; // blur sigma, screen px
  // Fainter at the city view, where many more threads overlap per pixel.
  final fade = ui.lerpDouble(0.4, 1, ((zoom - 11) / 4).clamp(0.0, 1.0))!;
  double alpha(int trips) =>
      (0.08 + 0.42 * math.min(1.0, math.sqrt(trips / 260))) * fade;
  // Light adds up on the dark map; on the light map ink lays over ink.
  final blend = dark ? BlendMode.plus : BlendMode.srcOver;

  void threads(double widthPx, double k) {
    canvas.save();
    canvas.translate(at.origin.dx, at.origin.dy);
    canvas.rotate(at.angle);
    canvas.scale(at.scale);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = widthPx / at.scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = blend;
    for (final type in _order) {
      if (types.isNotEmpty && !types.contains(type)) continue;
      final (onDark, onLight) = _colors[type]!;
      final base = dark ? onDark : onLight;
      for (var i = 0; i < traces.traces.length; i++) {
        final tr = traces.traces[i];
        if (tr.type != type) continue;
        paint.color = base.withValues(alpha: alpha(tr.trips) * k);
        canvas.drawPath(paths[i], paint);
      }
    }
    canvas.restore();
  }

  // One layer of our own, so `plus` adds threads to threads, never to the map.
  canvas.saveLayer(bounds, Paint());
  canvas.saveLayer(
    bounds,
    Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: glow, sigmaY: glow),
  );
  threads(core * 3, dark ? 0.6 : 0.35);
  canvas.restore();
  threads(core, 1);
  canvas.restore();
}
