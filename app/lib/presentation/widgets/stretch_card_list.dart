import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/design/stize_tokens.dart';

/// An edge-to-edge card list whose first and last cards stretch when the list
/// is pulled past its ends, then spring back (owner, 2026-11-25).
///
/// Pulling down past the top fills the gap with the first card's colour and
/// shows the refresh button in it; releasing past the trigger refreshes, and
/// the stretched band holds the spinning button until the fetch is done.
/// Pulling up past the bottom fills the gap under the last card with its
/// colour. A null colour leaves that edge plain (a banner leads the list).
class StretchCardList extends StatefulWidget {
  const StretchCardList({
    super.key,
    required this.children,
    this.controller,
    this.bottomPadding = 0,
    this.topColor,
    this.bottomColor,
    this.onRefresh,
  });

  final List<Widget> children;
  final ScrollController? controller;

  /// Space under the last card (the safe area); the bottom stretch sits
  /// between the card and it.
  final double bottomPadding;

  final Color? topColor;
  final Color? bottomColor;
  final Future<void> Function()? onRefresh;

  @override
  State<StretchCardList> createState() => _StretchCardListState();
}

class _StretchCardListState extends State<StretchCardList> {
  // Scroll notifications also arrive during layout, so the fills repaint from
  // this notifier instead of rebuilding.
  final _edges = _Edges();

  // Marks where the last card ends; measured after layout.
  final _endKey = GlobalKey();

  @override
  void dispose() {
    _edges.dispose();
    super.dispose();
  }

  void _measure() {
    final end = _endKey.currentContext?.findRenderObject() as RenderBox?;
    final me = context.findRenderObject() as RenderBox?;
    if (end == null || me == null || !end.attached || !me.attached) return;
    _edges.contentEnd =
        end.localToGlobal(Offset.zero, ancestor: me).dy + _edges.pixels;
    _edges.changed();
  }

  bool _measureQueued = false;

  // Cards animate their size in and out, so the end is re-measured after any
  // frame a scroll happened in.
  void _queueMeasure() {
    if (_measureQueued) return;
    _measureQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureQueued = false;
      if (mounted) _measure();
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    _queueMeasure();
    final m = n.metrics;
    _edges
      ..top = (m.minScrollExtent - m.pixels).clamp(0.0, double.infinity)
      ..bottom = (m.pixels - m.maxScrollExtent).clamp(0.0, double.infinity)
      ..pixels = m.pixels
      ..changed();
    return false;
  }

  Widget _refresh(
    BuildContext context,
    RefreshIndicatorMode mode,
    double pulled,
    double trigger,
    double extent,
  ) {
    if (pulled < 1) return const SizedBox.shrink();
    final c = StizeColors.of(context);
    final progress = (pulled / trigger).clamp(0.0, 1.0);
    final busy =
        mode == RefreshIndicatorMode.refresh ||
        mode == RefreshIndicatorMode.armed;
    return ClipRect(
      child: OverflowBox(
        maxHeight: double.infinity,
        // One extra pixel tucks under the first card: no seam between the
        // band and the card it stretches.
        alignment: Alignment.topCenter,
        child: Container(
          height: pulled + 1,
          color: widget.topColor,
          alignment: Alignment.center,
          child: Opacity(
            opacity: progress,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.raised,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(color: Color(0x33000000), blurRadius: 8),
                ],
              ),
              alignment: Alignment.center,
              child: busy
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: c.ink,
                      ),
                    )
                  : Transform.rotate(
                      angle: progress * 3.14159 * 1.5,
                      child: Icon(Icons.refresh, size: 22, color: c.ink),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _queueMeasure();
    final list = CustomScrollView(
      controller: widget.controller,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        if (widget.onRefresh != null)
          CupertinoSliverRefreshControl(
            onRefresh: widget.onRefresh,
            refreshTriggerPullDistance: 96,
            refreshIndicatorExtent: 64,
            builder: _refresh,
          ),
        SliverPadding(
          padding: EdgeInsets.only(bottom: widget.bottomPadding),
          sliver: SliverList.list(
            children: [
              ...widget.children,
              SizedBox(key: _endKey, height: 0),
            ],
          ),
        ),
      ],
    );
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: CustomPaint(
        painter: _EdgePainter(
          _edges,
          // With a refresh control the top band paints itself (and holds
          // while refreshing).
          top: widget.onRefresh == null ? widget.topColor : null,
          bottom: widget.bottomColor,
          bottomPadding: widget.bottomPadding,
        ),
        child: list,
      ),
    );
  }
}

class _Edges extends ChangeNotifier {
  double top = 0;
  double bottom = 0;
  double pixels = 0;
  double? contentEnd;

  void changed() => notifyListeners();
}

/// Paints the stretched first and last card under the list.
class _EdgePainter extends CustomPainter {
  _EdgePainter(
    this.edges, {
    required this.top,
    required this.bottom,
    required this.bottomPadding,
  }) : super(repaint: edges);

  final _Edges edges;
  final Color? top;
  final Color? bottom;
  final double bottomPadding;

  @override
  void paint(Canvas canvas, Size size) {
    if (top != null && edges.top > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, edges.top),
        Paint()..color = top!,
      );
    }
    final end = edges.contentEnd;
    if (bottom != null && edges.bottom > 0 && end != null) {
      final y = end - edges.pixels;
      // The safe-area strip fades in first, so the card reads as one piece
      // stretching down; then the pull itself.
      final fade = (edges.bottom / 12).clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, bottomPadding),
        Paint()..color = bottom!.withValues(alpha: bottom!.a * fade),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, y + bottomPadding, size.width, edges.bottom),
        Paint()..color = bottom!,
      );
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.top != top || old.bottom != bottom || old.bottomPadding != bottomPadding;
}
