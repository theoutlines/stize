import 'package:flutter/widgets.dart';

import '../../core/design/stize_tokens.dart';

/// A column whose children animate in and out instead of popping (owner,
/// 2026-11-23: cards vanishing and appearing at once on a refresh read as
/// flicker). A new child grows and fades in; a removed one fades and collapses
/// before it leaves, so the cards below slide rather than jump. Children are
/// matched by their [Key] (every child needs a unique one), so a reordered or
/// updated card keeps its place and state.
class AnimatedEntries extends StatefulWidget {
  const AnimatedEntries({
    super.key,
    required this.children,
    this.gap = 0,
    this.duration = StizeMotion.fast,
  });

  final List<Widget> children;

  /// Space between children (part of each child's animated height, so a gap
  /// collapses together with the card it follows).
  final double gap;
  final Duration duration;

  @override
  State<AnimatedEntries> createState() => _AnimatedEntriesState();
}

class _Entry {
  _Entry(this.key, this.child, this.controller);
  final Key key;
  Widget child;
  final AnimationController controller;
  bool leaving = false;
}

class _AnimatedEntriesState extends State<AnimatedEntries>
    with TickerProviderStateMixin {
  final List<_Entry> _entries = [];

  @override
  void initState() {
    super.initState();
    // First build: no entrance animation, the list is just there.
    for (final (k, c) in _keyed(widget.children)) {
      _entries.add(_Entry(k, c, _controller(value: 1)));
    }
  }

  /// Children keyed uniquely: a repeated key gets an occurrence suffix, so a
  /// caller's accidental duplicate can't crash the column.
  static List<(Key, Widget)> _keyed(List<Widget> children) {
    final seen = <Key, int>{};
    return [
      for (final c in children)
        () {
          final k = c.key!;
          final n = seen[k] = (seen[k] ?? 0) + 1;
          return (n == 1 ? k : ValueKey((k, n)), c);
        }(),
    ];
  }

  AnimationController _controller({required double value}) =>
      AnimationController(
        vsync: this,
        duration: widget.duration,
        // Leaving is quicker and quieter than entering.
        reverseDuration: StizeMotion.quick,
        value: value,
      );

  @override
  void didUpdateWidget(AnimatedEntries old) {
    super.didUpdateWidget(old);
    final byKey = {for (final e in _entries) e.key: e};
    final next = <_Entry>[];
    final incoming = <Key>{};
    for (final (k, c) in _keyed(widget.children)) {
      incoming.add(k);
      final existing = byKey[k];
      if (existing != null) {
        existing.child = c;
        if (existing.leaving) {
          existing.leaving = false;
          existing.controller.forward();
        }
        next.add(existing);
      } else {
        final e = _Entry(k, c, _controller(value: 0))..controller.forward();
        next.add(e);
      }
    }
    // Leaving entries stay at their old position while they collapse.
    for (var i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      if (incoming.contains(e.key)) continue;
      if (!e.leaving) {
        e.leaving = true;
        e.controller.reverse().whenComplete(() {
          // Came back meanwhile, or the widget is gone (dispose() owns it).
          if (!mounted || !e.leaving) return;
          setState(() => _entries.remove(e));
          e.controller.dispose();
        });
      }
      next.insert(i.clamp(0, next.length), e);
    }
    _entries
      ..clear()
      ..addAll(next);
  }

  @override
  void dispose() {
    for (final e in _entries) {
      e.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _entries.length; i++)
          KeyedSubtree(
            key: _entries[i].key,
            child: SizeTransition(
              sizeFactor: CurvedAnimation(
                parent: _entries[i].controller,
                curve: StizeMotion.smoothOut,
              ),
              // Was axisAlignment: -1 (vertical): grow from the top.
              alignment: Alignment.topLeft,
              child: FadeTransition(
                opacity: _entries[i].controller,
                child: Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : widget.gap),
                  child: IgnorePointer(
                    ignoring: _entries[i].leaving,
                    child: _entries[i].child,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
