import 'package:stize/core/design/stize_tokens.dart';
import 'package:flutter/material.dart';
import 'package:stize/core/design/stize_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/jam.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../../core/design/stize_icons.dart';
import 'notice_strip.dart';

/// The jams that touch a line in the current Nearby context, the strip's
/// content; empty when detection is off or the feed has nothing. Shared so the
/// list knows the strip is there (its top stretch takes the strip's colour).
List<Jam> nearbyJams(WidgetRef ref, Set<String> contextLines) {
  if (!ref.watch(jamDetectionEnabledProvider)) return const [];
  final board = ref.watch(jamsProvider).valueOrNull;
  if (board == null) return const [];
  final ctx = contextLines.map((l) => l.toLowerCase()).toSet();
  return board.activeJams
      .where((j) => ctx.contains(j.line.toLowerCase()))
      .toList();
}

/// DS Banner, jam: `jam` at 13%.
Color jamSurface(StizeColors c) => c.jam.withValues(alpha: 0.13);

/// The jam notice at the top of the Nearby list: one NoticeStrip per active
/// jam on a line the user could be waiting for. It opens the list and scrolls
/// with it, like the guide strip; a tap shows the affected stops. Observation
/// tone, matching the stop banner; inert unless the flag is on.
class JamNearbyStrip extends ConsumerStatefulWidget {
  const JamNearbyStrip({super.key, required this.contextLines});

  /// The line numbers currently shown in the Nearby list.
  final Set<String> contextLines;

  @override
  ConsumerState<JamNearbyStrip> createState() => _JamNearbyStripState();
}

class _JamNearbyStripState extends ConsumerState<JamNearbyStrip> {
  final _expanded = <String>{}; // jam keys currently expanded

  @override
  Widget build(BuildContext context) {
    final jams = nearbyJams(ref, widget.contextLines);
    if (jams.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final j in jams) _row(context, j)],
    );
  }

  Widget _row(BuildContext context, Jam jam) {
    final l10n = AppLocalizations.of(context);
    final key = '${jam.line}|${jam.directionRouteId}';
    final open = _expanded.contains(key);
    return NoticeStrip(
      icon: StizeIcons.hourglass,
      title: l10n.jamNearbyDelay(jam.line),
      surface: jamSurface(StizeColors.of(context)),
      open: open,
      details: _affectedStops(context, jam),
      onTap: () => setState(() {
        open ? _expanded.remove(key) : _expanded.add(key);
      }),
    );
  }

  Widget _affectedStops(BuildContext context, Jam jam) {
    final l10n = AppLocalizations.of(context);
    // Resolve affected stop ids → names from the offline GTFS cache (already
    // loaded; cheap). Best-effort — unknown ids are simply omitted.
    return FutureBuilder(
      future: ref.read(gtfsOfflineCacheProvider).getStops(),
      builder: (context, snap) {
        final stops = snap.data ?? const [];
        final names = [
          for (final s in stops)
            if (jam.affectedStopIds.contains(s.stopId)) s.name,
        ];
        if (names.isEmpty) return const SizedBox.shrink();
        final text = StizeText.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.jamAffectedStopsTitle, style: text.caption),
            const SizedBox(height: StizeSpace.space1),
            Text(
              names.join(' · '),
              style: text.body.copyWith(color: StizeColors.of(context).ink75),
            ),
          ],
        );
      },
    );
  }
}
