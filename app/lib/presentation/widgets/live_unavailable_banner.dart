import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// A thin note above an arrivals list: the live board is down, so what follows
/// is the timetable.
///
/// Deliberately quiet — the list underneath is still useful, and a night board
/// looks the same. Shared by both shutters (`stop_sheet` in-app and
/// `stop_screen` deep-link) and the Nearby list, so the three can't drift.
class LiveUnavailableBanner extends StatelessWidget {
  const LiveUnavailableBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: Row(
        children: [
          Icon(Icons.schedule_outlined, size: 16, color: scheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.liveUnavailableBanner,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}
