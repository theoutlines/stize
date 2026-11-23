import 'package:flutter/material.dart';
import 'package:stize/core/design/stize_text.dart';

import '../../core/design/stize_tokens.dart';

import '../../core/external_link.dart';
import '../../domain/models/route_alert.dart';
import '../../l10n/app_localizations.dart';
import '../../core/design/stize_icons.dart';

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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    hasHigh ? StizeIcons.warning : StizeIcons.info,
                    size: 18,
                    color: headerFg,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${l10n.alertsBannerTitle} · ${alerts.length}',
                      style: StizeText.of(context).label.copyWith(
                        color: headerFg,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? StizeIcons.chevronUp : StizeIcons.chevronDown,
                    color: headerFg,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final alert in alerts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
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
                ? StizeIcons.clock
                : (high ? StizeIcons.warning : StizeIcons.info),
            color: fg,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.isUpcoming
                      ? l10n.alertUpcomingLabel
                      : l10n.alertActiveLabel,
                  style: StizeText.of(
                    context,
                  ).control.copyWith(color: fg, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  alert.localizedSummary(
                    Localizations.localeOf(context).languageCode,
                  ),
                  style: StizeText.of(context).body.copyWith(color: fg),
                ),
                const SizedBox(height: StizeSpace.space3),
                // The system tertiary button as is (owner, 2026-11-23: the
                // zero-padding version hugged the label and looked crooked).
                TextButton(
                  onPressed: () => openExternalUrl(alert.url),
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
