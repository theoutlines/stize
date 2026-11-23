import 'package:stize/core/design/stize_tokens.dart';
import 'package:flutter/material.dart';
import 'package:stize/core/design/stize_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/jam.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../../core/design/stize_icons.dart';

/// A muted strip at the top of the Nearby list: one soft row per active jam that
/// touches a line in the current Nearby context. Tap to expand the affected stop
/// names. Observation tone, matching the stop banner; inert unless the flag is on
/// and the feed is healthy.
class JamNearbyStrip extends ConsumerStatefulWidget {
  const JamNearbyStrip({super.key, required this.contextLines});

  /// The line numbers currently shown in the Nearby list — the strip only
  /// surfaces jams the user could actually be waiting for.
  final Set<String> contextLines;

  @override
  ConsumerState<JamNearbyStrip> createState() => _JamNearbyStripState();
}

class _JamNearbyStripState extends ConsumerState<JamNearbyStrip> {
  final _expanded = <String>{}; // jam keys currently expanded

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(jamDetectionEnabledProvider)) return const SizedBox.shrink();
    final board = ref.watch(jamsProvider).valueOrNull;
    if (board == null) return const SizedBox.shrink();
    final ctx = widget.contextLines.map((l) => l.toLowerCase()).toSet();
    final jams = board.activeJams
        .where((j) => ctx.contains(j.line.toLowerCase()))
        .toList();
    if (jams.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final j in jams) _row(context, j)],
    );
  }

  Widget _row(BuildContext context, Jam jam) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final key = '${jam.line}|${jam.directionRouteId}';
    final open = _expanded.contains(key);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: StizeColors.of(context).jam.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() {
              open ? _expanded.remove(key) : _expanded.add(key);
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    StizeIcons.hourglass,
                    size: 16,
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.jamNearbyDelay(jam.line),
                      style: StizeText.of(
                        context,
                      ).caption.copyWith(color: theme.colorScheme.onSurface),
                    ),
                  ),
                  Icon(
                    open ? StizeIcons.chevronUp : StizeIcons.chevronDown,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (open) _affectedStops(context, jam),
        ],
      ),
    );
  }

  Widget _affectedStops(BuildContext context, Jam jam) {
    final theme = Theme.of(context);
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(40, 0, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.jamAffectedStopsTitle,
                style: StizeText.of(
                  context,
                ).note.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                names.join(' · '),
                style: StizeText.of(
                  context,
                ).caption.copyWith(color: theme.colorScheme.onSurface),
              ),
            ],
          ),
        );
      },
    );
  }
}
