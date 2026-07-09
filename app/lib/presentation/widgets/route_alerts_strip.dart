import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/route_alert.dart';
import '../../l10n/app_localizations.dart';

/// Route-change alerts, shown compactly (H1/H3).
///
/// The old design stacked full-width red cards over the map — loud and
/// space-hungry. Instead:
///  * a single alert renders as one quiet inline row;
///  * several collapse behind a short "Transport changes (N)" banner that
///    expands on tap, so the map/sheet isn't buried under a wall of warnings.
///
/// Tone is deliberately calm: routine route changes use a neutral surface;
/// only genuinely disruptive ones ([RouteAlert.isHighSeverity]) get a warmer,
/// more noticeable treatment — these are ordinary "it happens" notices, not
/// "the city has stopped".
class RouteAlertsStrip extends StatefulWidget {
  const RouteAlertsStrip({super.key, required this.alerts});

  final List<RouteAlert> alerts;

  @override
  State<RouteAlertsStrip> createState() => _RouteAlertsStripState();
}

class _RouteAlertsStripState extends State<RouteAlertsStrip> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final alerts = widget.alerts;
    if (alerts.isEmpty) return const SizedBox.shrink();

    // A lone alert is never worth a collapse affordance — just show it.
    if (alerts.length == 1) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: _AlertRow(alert: alerts.first),
      );
    }

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hasHigh = alerts.any((a) => a.isHighSeverity && a.isActiveNow);
    final headerColor = hasHigh
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHighest;
    final headerFg = hasHigh
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    hasHigh
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline_rounded,
                    size: 18,
                    color: headerFg,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${l10n.alertsBannerTitle} · ${alerts.length}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: headerFg,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: headerFg,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final alert in alerts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _AlertRow(alert: alert),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One compact alert: a coloured status dot, the label + summary, and a
/// read-more link. Calm surface unless the alert is high-severity and active.
class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final RouteAlert alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final high = alert.isHighSeverity && alert.isActiveNow;

    final Color bg;
    final Color fg;
    if (high) {
      bg = theme.colorScheme.errorContainer;
      fg = theme.colorScheme.onErrorContainer;
    } else {
      bg = theme.colorScheme.surfaceContainerHighest;
      fg = theme.colorScheme.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            alert.isUpcoming
                ? Icons.schedule
                : (high
                      ? Icons.warning_amber_rounded
                      : Icons.info_outline_rounded),
            color: fg,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.isUpcoming
                      ? l10n.alertUpcomingLabel
                      : l10n.alertActiveLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  alert.localizedSummary(
                    Localizations.localeOf(context).languageCode,
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    foregroundColor: fg,
                  ),
                  onPressed: () => launchUrl(
                    Uri.parse(alert.url),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(l10n.alertReadMore),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
