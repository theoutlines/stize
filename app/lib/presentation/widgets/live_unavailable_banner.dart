import 'package:stize/core/design/stize_text.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../core/design/stize_icons.dart';

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
          Icon(StizeIcons.clock, size: 16, color: scheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.liveUnavailableBanner,
              style: StizeText.of(
                context,
              ).caption.copyWith(color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}
