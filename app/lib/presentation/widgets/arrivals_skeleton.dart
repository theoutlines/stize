import 'package:flutter/material.dart';

import '../../core/design/stize_tokens.dart';

/// The stop board while its arrivals load: the shape of three arrival cards
/// (line badge, direction, the big ETA, the next departures), the same way
/// the app's launch skeleton stands in for the first screen. Announced to
/// screen readers as [label].
class ArrivalsSkeleton extends StatelessWidget {
  const ArrivalsSkeleton({super.key, required this.label, this.rows = 3});

  final String label;
  final int rows;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    return Semantics(
      label: label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows; i++)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.fill05,
                  border: Border(bottom: BorderSide(color: c.line)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(StizeSpace.space4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _block(c, width: 64, height: 32),
                            const SizedBox(height: StizeSpace.space3),
                            _block(c, width: 160, height: 16),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _block(c, width: 72, height: 40),
                          const SizedBox(height: StizeSpace.space4),
                          _block(c, width: 112, height: 16),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Widget _block(
    StizeColors c, {
    required double width,
    required double height,
  }) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: c.fill10,
      borderRadius: BorderRadius.circular(8),
    ),
  );
}
