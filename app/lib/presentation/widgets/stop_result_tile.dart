import 'package:flutter/material.dart';

import '../../core/map_support.dart';
import '../../core/design/stize_tokens.dart';
import '../../domain/models/stop.dart';

/// DS StopRow: one stop in search results, the same row on mobile (Nearby
/// search) and desktop (panel search). The stop's map pin, name, the lines
/// that serve it, and the sign number as a Chip on the right, so a stop found
/// by its number shows that number and two same-named stops (one per
/// direction) tell apart.
class StopResultTile extends StatelessWidget {
  const StopResultTile({super.key, required this.stop, this.onTap});

  final Stop stop;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    final code = stop.code;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      // The pin the stop has on the map (type colour and glyph), so search
      // speaks the map's language; 48 px pin box drawn at 32.
      leading: SizedBox.square(
        dimension: 32,
        child: FittedBox(child: stopPinFor(stop, Theme.of(context).colorScheme)),
      ),
      title: Text(stop.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: stop.lines.isEmpty
          ? null
          : Text(
              stop.lines.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: code == null ? null : StopCodeChip(code: code),
      onTap: onTap,
    );
  }
}

/// The stop's sign number as a DS Chip: `control` 12/16 on `fill-08`, a pill.
class StopCodeChip extends StatelessWidget {
  const StopCodeChip({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.fill08,
        borderRadius: BorderRadius.circular(StizeRadius.radiusPill),
      ),
      child: Text(code, style: StizeType.control.copyWith(color: c.ink75)),
    );
  }
}
