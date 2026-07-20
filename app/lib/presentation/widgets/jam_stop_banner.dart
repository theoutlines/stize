import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/route_alert.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';

/// The soft delay banner shown on a stop board that is *downstream* of a detected
/// tram jam, plus the neutral bus-substitution notice. Tone is deliberately an
/// observation ("stopped longer than usual — possible delay"), never a claim of a
/// breakdown. Inert unless `jam_detection_show` is on and the feed is healthy.
class JamStopBanner extends ConsumerWidget {
  const JamStopBanner({super.key, required this.stopId, required this.lines});

  final String stopId;

  /// Lines this stop serves — used to match substitution notices to the stop.
  final List<String> lines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(jamDetectionEnabledProvider)) return const SizedBox.shrink();
    final board = ref.watch(jamsProvider).valueOrNull;
    if (board == null || !board.feedHealthy) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final alerts = ref.watch(alertsProvider).valueOrNull ?? const <RouteAlert>[];

    final widgets = <Widget>[];

    // Delay banner: a jam lists this stop as downstream.
    final jam = board.downstreamJamAt(stopId);
    if (jam != null) {
      widgets.add(_banner(
        context,
        icon: Icons.hourglass_bottom,
        text: l10n.jamStopBannerTitle(jam.line),
      ));
    }

    // Substitution notice: a bus is running one of this stop's tram lines. If a
    // route alert already announced it, it's planned — keep the same neutral tone
    // (no extra loudness), so this notice is purely informational either way.
    final servedSubs = board.substitutions
        .where((s) => lines.any((l) => l.toLowerCase() == s.line.toLowerCase()))
        .map((s) => s.line)
        .toSet();
    for (final line in servedSubs) {
      // Skip if we already surface it via a route alert to avoid double-telling.
      final announced = alerts.any((a) => !a.isExpired && a.matchesLine(line));
      if (announced) continue;
      widgets.add(_banner(
        context,
        icon: Icons.directions_bus_filled_outlined,
        text: l10n.jamSubstitutionNotice(line),
      ));
    }

    if (widgets.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: widgets);
  }

  Widget _banner(BuildContext context, {required IconData icon, required String text}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
