import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
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
    this.shrinkWrap = false,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;
  final ScrollController? controller;

  /// Space under the last card (the safe area); the bottom stretch sits
  /// between the card and it.
  final double bottomPadding;

  final Color? topColor;
  final Color? bottomColor;
  final Future<void> Function()? onRefresh;

  /// Hug the content (desktop island) instead of filling the height.
  final bool shrinkWrap;

  /// Inset around the children, for lists of rows rather than cards.
  final EdgeInsets padding;

  @override
  State<StretchCardList> createState() => _StretchCardListState();
}

class _StretchCardListState extends State<StretchCardList> {
  // Scroll notifications also arrive during layout, so the fills repaint from
  // this notifier instead of rebuilding.
  final _edges = _Edges();

  // Marks where the last card ends; measured after layout.
  final _endKey = GlobalKey();

  // Used when the host passes no controller: the wheel rubber band needs the
  // position.
  ScrollController? _ownController;
  ScrollController get _controller =>
      widget.controller ?? (_ownController ??= ScrollController());

  @override
  void dispose() {
    _ownController?.dispose();
    _edges.dispose();
    super.dispose();
  }

  /// A mouse wheel or a trackpad on the web scrolls by pointer signals, which
  /// stop dead at the ends: no stretch, and the browser's own page bounce
  /// showed instead (owner, 2026-11-26). At an end the signal pushes the list
  /// past it with growing resistance; each push springs back on its own, so
  /// the bounce settles as soon as the wheel goes quiet.
  // While the wheel holds the list past an end, the scrollable must not take
  // the next signal itself: it would clamp the list back to the end, and the
  // pull flickered between stretched and not (owner, 2026-11-26).
  bool _wheelPull = false;
  late final _physics = _WheelPullPhysics(() => _wheelPull);

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final c = _controller;
    if (!c.hasClients || c.positions.length != 1) return;
    final p = c.position;
    final dy = e.scrollDelta.dy;
    final atTop = dy < 0 && p.pixels <= p.minScrollExtent;
    final atEnd = dy > 0 && p.pixels >= p.maxScrollExtent;
    if (!atTop && !atEnd) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (_) {
      _wheelPull = true;
      final over = atTop
          ? p.minScrollExtent - p.pixels
          : p.pixels - p.maxScrollExtent;
      // Stiff, like a drag's rubber band: the pull slows fast and tops out
      // well short of the list (owner, 2026-11-26: half the screen took one
      // flick). Reaching the refresh trigger takes a deliberate pull.
      const reach = 96.0;
      final give = (1 - over / reach).clamp(0.0, 1.0);
      if (give <= 0) return;
      p.jumpTo(p.pixels + dy * 0.4 * give * give);
    });
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
    if (_wheelPull && !m.outOfRange) _wheelPull = false;
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
      child: LayoutBuilder(
        builder: (context, box) => OverflowBox(
          maxHeight: double.infinity,
          // Fills the whole box the control gives it, which can be taller than
          // the pull while it refreshes (a dark strip showed above the band,
          // owner 2026-11-26), plus one pixel tucked under the first card so
          // there is no seam.
          alignment: Alignment.topCenter,
          child: Container(
            height:
                (box.maxHeight.isFinite
                    ? (box.maxHeight > pulled ? box.maxHeight : pulled)
                    : pulled) +
                1,
            color: widget.topColor == null
                ? null
                : Color.alphaBlend(
                    widget.topColor!,
                    Theme.of(context).colorScheme.surface,
                  ),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _queueMeasure();
    final list = CustomScrollView(
      controller: _controller,
      shrinkWrap: widget.shrinkWrap,
      physics: _physics,
      slivers: [
        if (widget.onRefresh != null)
          CupertinoSliverRefreshControl(
            onRefresh: widget.onRefresh,
            // Reachable within the resting sheet: bouncing friction makes 96 px
            // of stretch need a long finger travel (owner, 2026-11-26).
            refreshTriggerPullDistance: 64,
            refreshIndicatorExtent: 52,
            builder: _refresh,
          ),
        SliverPadding(
          padding:
              widget.padding.add(EdgeInsets.only(bottom: widget.bottomPadding))
                  as EdgeInsets,
          sliver: SliverList.list(
            children: [
              ...widget.children,
              SizedBox(key: _endKey, height: 0),
            ],
          ),
        ),
      ],
    );
    // Opaque over the sheet, so a translucent card (timetable, held back)
    // stretches to exactly what it looks like, and covers its own hairline.
    final under = Theme.of(context).colorScheme.surface;
    Color? solid(Color? c) => c == null ? null : Color.alphaBlend(c, under);
    return StretchCardEdges._(
      _edges,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: CustomPaint(
          painter: _EdgePainter(
            _edges,
            // The whole pull is painted here; the refresh control's own band
            // only covers the part it holds while refreshing, so on its own it
            // left an empty strip above the first row (owner, 2026-11-26).
            top: solid(widget.topColor),
            bottom: solid(widget.bottomColor),
            under: under,
            bottomPadding: widget.bottomPadding,
          ),
          foregroundPainter: _EdgePainter(
            _edges,
            top: null,
            bottom: solid(widget.bottomColor),
            under: under,
            bottomPadding: widget.bottomPadding,
            coverLine: true,
          ),
          child: Listener(onPointerSignal: _onSignal, child: list),
        ),
      ),
    );
  }
}

class _Edges extends ChangeNotifier {
  double top = 0;
  double bottom = 0;
  double pixels = 0;
  double? contentEnd;

  /// Set by the list's content when only it knows its last card (a stop
  /// board); wins over [StretchCardList.bottomColor].
  Color? reportedBottom;

  void changed() => notifyListeners();
}

/// Lets content inside a [StretchCardList] name the colour of its last card,
/// when the list itself can't know it (the stop board builds its cards deep
/// inside). Safe to call during build: the list only repaints.
class StretchCardEdges extends InheritedWidget {
  const StretchCardEdges._(this._edges, {required super.child});

  final _Edges _edges;

  static void reportLast(BuildContext context, Color? color) {
    final scope = context.getInheritedWidgetOfExactType<StretchCardEdges>();
    if (scope == null || scope._edges.reportedBottom == color) return;
    scope._edges.reportedBottom = color;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scope._edges.changed();
    });
  }

  @override
  bool updateShouldNotify(StretchCardEdges old) => false;
}

/// Paints the stretched first and last card under the list; as a foreground
/// painter ([coverLine]) it hides the last card's hairline while it stretches,
/// so the card reads as one piece (owner, 2026-11-25).
class _EdgePainter extends CustomPainter {
  _EdgePainter(
    this.edges, {
    required this.top,
    required this.bottom,
    required this.under,
    required this.bottomPadding,
    this.coverLine = false,
  }) : super(repaint: edges);

  final _Edges edges;
  final Color? top;
  final Color? bottom;
  final Color under;
  final double bottomPadding;
  final bool coverLine;

  @override
  void paint(Canvas canvas, Size size) {
    final reported = edges.reportedBottom;
    final bottomColor = reported != null
        ? Color.alphaBlend(reported, under)
        : bottom;
    final end = edges.contentEnd;
    if (coverLine) {
      if (bottomColor != null && edges.bottom > 0 && end != null) {
        canvas.drawRect(
          Rect.fromLTWH(0, end - edges.pixels - 1, size.width, 1),
          Paint()..color = bottomColor,
        );
      }
      return;
    }
    if (top != null && edges.top > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, edges.top),
        Paint()..color = top!,
      );
    }
    if (bottomColor != null && edges.bottom > 0 && end != null) {
      final y = end - edges.pixels;
      // The safe-area strip fades in first, so the card reads as one piece
      // stretching down; then the pull itself.
      final fade = (edges.bottom / 12).clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, bottomPadding),
        Paint()..color = bottomColor.withValues(alpha: fade),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, y + bottomPadding, size.width, edges.bottom),
        Paint()..color = bottomColor,
      );
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.top != top ||
      old.bottom != bottom ||
      old.under != under ||
      old.bottomPadding != bottomPadding;
}

/// Bouncing physics that turn the scrollable's own wheel handling off while a
/// wheel pull holds the list past an end (see [_StretchCardListState]).
class _WheelPullPhysics extends BouncingScrollPhysics {
  const _WheelPullPhysics(this.pulling)
    : super(parent: const AlwaysScrollableScrollPhysics());

  const _WheelPullPhysics._(this.pulling, ScrollPhysics? parent)
    : super(parent: parent);

  final bool Function() pulling;

  @override
  _WheelPullPhysics applyTo(ScrollPhysics? ancestor) =>
      _WheelPullPhysics._(pulling, buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      !pulling() && super.shouldAcceptUserOffset(position);
}
