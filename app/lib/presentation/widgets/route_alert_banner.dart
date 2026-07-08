import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/route_alert.dart';
import '../../l10n/app_localizations.dart';

/// Shows a route-change alert inline. Active changes get a full warning
/// treatment; upcoming ones get a quieter heads-up — per the project's rule
/// that future changes should be gentle until the date actually arrives.
class RouteAlertBanner extends StatelessWidget {
  const RouteAlertBanner({super.key, required this.alert});

  final RouteAlert alert;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isUpcoming = alert.isUpcoming;

    final background = isUpcoming ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.errorContainer;
    final foreground = isUpcoming ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onErrorContainer;

    return Card(
      color: background,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(isUpcoming ? Icons.schedule : Icons.warning_amber_rounded, color: foreground, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isUpcoming ? l10n.alertUpcomingLabel : l10n.alertActiveLabel,
                    style: theme.textTheme.labelMedium?.copyWith(color: foreground, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(alert.summary, style: theme.textTheme.bodyMedium?.copyWith(color: foreground)),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      foregroundColor: foreground,
                    ),
                    onPressed: () => launchUrl(Uri.parse(alert.url), mode: LaunchMode.externalApplication),
                    child: Text(l10n.alertReadMore),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
