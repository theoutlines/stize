import 'package:flutter/material.dart';

import 'notice_strip.dart';
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
    final l10n = AppLocalizations.of(context);
    final c = StizeColors.of(context);
    final locale = Localizations.localeOf(context).languageCode;

    // DS Banner, route alerts: calm, no red. An active disruption on
    // `fill-14` with a warning icon and `ink`; an ordinary notice on
    // `fill-08` with an info icon and `ink-75`. A flat NoticeStrip that opens
    // the list (owner, 2026-11-26).
    bool high(RouteAlert a) => a.isHighSeverity && a.isActiveNow;
    IconData iconFor(RouteAlert a) => a.isUpcoming
        ? StizeIcons.clock
        : (high(a) ? StizeIcons.warning : StizeIcons.info);

    // A lone alert is never worth a collapse affordance: its text shows.
    if (alerts.length == 1) {
      final a = alerts.single;
      return NoticeStrip(
        icon: iconFor(a),
        title: a.isUpcoming ? l10n.alertUpcomingLabel : l10n.alertActiveLabel,
        surface: high(a) ? c.fill14 : c.fill08,
        foreground: high(a) ? c.ink : c.ink75,
        body: _AlertBody(alert: a, locale: locale),
      );
    }

    final anyHigh = alerts.any(high);
    return NoticeStrip(
      icon: anyHigh ? StizeIcons.warning : StizeIcons.info,
      title: '${l10n.alertsBannerTitle} · ${alerts.length}',
      surface: anyHigh ? c.fill14 : c.fill08,
      foreground: anyHigh ? c.ink : c.ink75,
      open: _expanded,
      onTap: () => setState(() => _expanded = !_expanded),
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: StizeSpace.space3,
        children: [
          for (final a in alerts)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.isUpcoming
                      ? l10n.alertUpcomingLabel
                      : l10n.alertActiveLabel,
                  style: StizeText.of(context).control.copyWith(
                    color: high(a) ? c.ink : c.ink75,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: StizeSpace.space1),
                _AlertBody(alert: a, locale: locale),
              ],
            ),
        ],
      ),
    );
  }
}

/// One alert's text in `body` and the link to the source.
class _AlertBody extends StatelessWidget {
  const _AlertBody({required this.alert, required this.locale});

  final RouteAlert alert;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = StizeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          alert.localizedSummary(locale),
          style: StizeText.of(context).body.copyWith(color: c.ink75),
        ),
        // The system tertiary button as is (owner, 2026-11-23: the
        // zero-padding version hugged the label and looked crooked).
        TextButton(
          onPressed: () => openExternalUrl(alert.url),
          child: Text(l10n.alertReadMore),
        ),
      ],
    );
  }
}
