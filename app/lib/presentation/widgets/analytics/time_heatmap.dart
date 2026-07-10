import 'package:flutter/material.dart';

import '../../../domain/models/line_analytics.dart';
import 'analytics_palette.dart';

/// A GitHub-contributions-style grid: rows = days of week, columns = hours of
/// day, cell colour = a metric's intensity in that slot. The primary language
/// for time-of-day punctuality/reliability — you read "Friday evenings run red"
/// at a glance. Draws with [CustomPaint] (crisp squares, no extra dependency,
/// trivial light/dark theming).
class TimeHeatmap extends StatelessWidget {
  const TimeHeatmap({
    super.key,
    required this.grid,
    required this.valueOf,
    this.lowerIsBetter = true,
  });

  final List<AnalyticsCell> grid;

  /// The metric to colour by; null cells (no data) render faint.
  final double? Function(AnalyticsCell) valueOf;

  /// If true, a lower value is "better" (greener) — e.g. shorter interval.
  final bool lowerIsBetter;

  // Monday-first display order over the API's 0=Sunday..6=Saturday.
  static const _dowOrder = [1, 2, 3, 4, 5, 6, 0];
  static const _dowLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  Widget build(BuildContext context) {
    final matrix = List.generate(7, (_) => List<double?>.filled(24, null));
    double? lo, hi;
    for (final c in grid) {
      final v = valueOf(c);
      if (v == null) continue;
      final row = _dowOrder.indexOf(c.dow);
      if (row < 0 || c.hour < 0 || c.hour > 23) continue;
      matrix[row][c.hour] = v;
      lo = (lo == null || v < lo) ? v : lo;
      hi = (hi == null || v > hi) ? v : hi;
    }
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        const gutter = 30.0, bottom = 16.0, gap = 2.0;
        final cell = ((constraints.maxWidth - gutter - 23 * gap) / 24)
            .clamp(4.0, 24.0);
        final height = 7 * cell + 6 * gap + bottom;
        return SizedBox(
          width: double.infinity,
          height: height,
          child: CustomPaint(
            painter: _HeatmapPainter(
              matrix: matrix,
              lo: lo,
              hi: hi,
              lowerIsBetter: lowerIsBetter,
              emptyColor: AnalyticsPalette.empty(context),
              dowLabels: _dowLabels,
              labelStyle: labelStyle,
            ),
          ),
        );
      },
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.matrix,
    required this.lo,
    required this.hi,
    required this.lowerIsBetter,
    required this.emptyColor,
    required this.dowLabels,
    required this.labelStyle,
  });

  final List<List<double?>> matrix;
  final double? lo, hi;
  final bool lowerIsBetter;
  final Color emptyColor;
  final List<String> dowLabels;
  final TextStyle? labelStyle;

  static const _gutter = 30.0, _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = ((size.width - _gutter - 23 * _gap) / 24).clamp(4.0, 24.0);
    final span = (hi != null && lo != null) ? (hi! - lo!) : 0.0;
    final paint = Paint();

    for (var row = 0; row < 7; row++) {
      final y = row * (cell + _gap);
      for (var hour = 0; hour < 24; hour++) {
        final x = _gutter + hour * (cell + _gap);
        final v = matrix[row][hour];
        if (v == null) {
          paint.color = emptyColor;
        } else {
          var t = span <= 0 ? 0.5 : (v - lo!) / span;
          if (!lowerIsBetter) t = 1 - t;
          paint.color = AnalyticsPalette.reliability(t);
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, cell, cell),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      _text(canvas, dowLabels[row], Offset(0, y + cell / 2 - 6), width: _gutter - 6, right: true);
    }
    // Hour ticks along the bottom.
    for (final h in const [0, 6, 12, 18]) {
      final x = _gutter + h * (cell + _gap);
      _text(canvas, '$h', Offset(x, 7 * (cell + _gap)));
    }
  }

  void _text(Canvas canvas, String s, Offset at, {double? width, bool right = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = right && width != null ? width - tp.width : at.dx;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) =>
      old.matrix != matrix || old.lo != lo || old.hi != hi || old.emptyColor != emptyColor;
}
