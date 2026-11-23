import 'package:flutter/material.dart';

import '../../core/arrival_display.dart';
import '../../core/design/stize_tokens.dart';
import '../../core/eta_format.dart';
import '../../core/fleet_matcher.dart';
import '../../domain/models/arrival.dart';
import '../../l10n/app_localizations.dart';
import 'fleet_badges.dart';
import 'stize_transit_card.dart';
import '../../core/design/stize_icons.dart';

class ArrivalTile extends StatelessWidget {
  const ArrivalTile({
    super.key,
    required this.arrival,
    this.etaDeltaMinutes,
    this.fleet,
    this.onOpenFleetCard,
    this.onTap,
    this.emphasis = false,
    this.destination,
    this.nextEtaMinutes,
    this.headwayMinutes,
    this.laterEtaMinutes = const [],
  });

  final Arrival arrival;

  /// Optional row tap — e.g. to focus this vehicle on the map.
  final VoidCallback? onTap;

  /// Resolved Fleet-ID for this arrival's vehicle, or null when the feature is
  /// off (asset missing/invalid — B5). Drives the compact badges (B2).
  final FleetVehicle? fleet;

  /// Opens the model card (B3). Only wired when [fleet] carries model info.
  final VoidCallback? onOpenFleetCard;

  /// How this line's ETA changed since the previous refresh, in minutes
  /// (positive = now arriving *later*, negative = *sooner*), or null when
  /// unchanged / first seen. Drives the explicit "time changed" badge (G1) so
  /// a silently shifting number doesn't quietly erode trust.
  final int? etaDeltaMinutes;

  /// Stiže card only: the first (nearest) card is rendered larger — padding 16
  /// and a 28/32 line number instead of 20/24.
  final bool emphasis;

  /// Stiže card only: the line's destination ("→ Vukov spomenik"), resolved
  /// from the GTFS line directory. Null hides the direction row (the per-stop
  /// upstream doesn't carry a headsign).
  final String? destination;

  /// Stiže card only: when the same line comes again, that next ETA in minutes —
  /// rendered in the caption as "next in N min" / "next at HH:MM". Null hides it.
  final int? nextEtaMinutes;

  /// Stiže card only: the line's planned interval at this hour (timetable),
  /// shown as "every ~N min" when the board has no second trip of this line to
  /// name. Null hides it. (Adaptive: measured intervals and "often late" will
  /// take this slot once analytics has enough samples.)
  final int? headwayMinutes;

  /// Stiže card only: ETAs of the later vehicles of this line×direction folded
  /// into this card (one card per direction), shown small under the big ETA.
  final List<int> laterEtaMinutes;

  @override
  Widget build(BuildContext context) {
    return _card(context, StizeColors.of(context));
  }

  // ───────────────────────── Stiže card (flag ON) ─────────────────────────

  Widget _card(BuildContext context, StizeColors c) {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final status = arrivalRowStatus(arrival);
    final live = status == ArrivalRowStatus.live;
    return StizeTransitCard(
      type: arrival.vehicleType,
      line: arrival.line,
      destination: destination,
      caption: _caption(
        context,
        c,
        StizeTransitCard.onFor(c, status == ArrivalRowStatus.scheduled),
        status,
        live,
        l10n,
        localeName,
      ),
      etaMinutes: arrival.etaMinutes,
      scheduled: status == ArrivalRowStatus.scheduled,
      etaFooter: _cardFooter(c, status, l10n, localeName),
      live: live,
      emphasis: emphasis,
      onTap: live ? onTap : null,
    );
  }

  /// Caption line (12/16, white 80%): live dot, stops-away / status, the next
  /// trip of this line, and the Fleet-ID / comfort badges. Wrapped so a long
  /// run never clips a colour card.
  List<Widget> _caption(
    BuildContext context,
    StizeColors c,
    Color on,
    ArrivalRowStatus status,
    bool live,
    AppLocalizations l10n,
    String localeName,
  ) {
    final style = StizeTransitCard.captionStyle(
      c,
      scheduled: status == ArrivalRowStatus.scheduled,
    );

    // Primary descriptor: stops-away for a live row, the honest status word for
    // the rest. `arrivalProximity` guards the junk `stops_remaining = 0`.
    String? primary;
    if (live) {
      primary = switch (arrivalProximity(
        stopsRemaining: arrival.stopsRemaining,
        etaMinutes: arrival.etaMinutes,
      )) {
        ArrivalProximity.here => l10n.arrivalStopsAway(0),
        ArrivalProximity.stopsAway => l10n.arrivalStopsAway(
          arrival.stopsRemaining!,
        ),
        ArrivalProximity.unknown => null,
      };
    } else {
      primary = status == ArrivalRowStatus.scheduled
          ? l10n.arrivalScheduled
          : l10n.arrivalExpected;
    }

    // The next trip of this line, with its unit always attached.
    String? next;
    if (nextEtaMinutes != null) {
      next = nextEtaMinutes! >= kFarEtaMinutes
          ? l10n.arrivalNextAt(clockAt(localeName, nextEtaMinutes!))
          : l10n.arrivalNextIn(nextEtaMinutes! <= 0 ? 0 : nextEtaMinutes!);
    }

    // Planned interval: only when no next trip is on the board, so a card
    // carries one "how often" fact, never two.
    final every = (next == null && headwayMinutes != null)
        ? l10n.arrivalEvery(headwayMinutes!)
        : null;

    final hasText = primary != null || next != null || every != null;
    final strip = (fleet == null || status == ArrivalRowStatus.scheduled)
        ? null
        : FleetBadgeStrip(
            fleet: fleet!,
            garageNo: arrival.garageNo,
            onTap: fleet!.hasInfo ? onOpenFleetCard : null,
            onColor: on,
          );

    final parts = <Widget>[
      // A small white dot marks a genuinely live vehicle; only shown alongside
      // text, never as a lone dot.
      if (live && hasText) StizeTransitCard.liveDot(c),
      if (primary != null) Text(primary, style: style),
      if (next != null) Text(next, style: style),
      // Interval: a repeat glyph + "~8 min" (short, so the badges never push
      // it into an ellipsis).
      if (every != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(StizeIcons.repeat, size: 13, color: style.color),
            const SizedBox(width: 2),
            Text(every, style: style),
          ],
        ),
      ?strip,
    ];
    return parts;
  }

  /// Under the big ETA: the ETA-change hint (G1) and the later trips of this
  /// direction folded into the card ("7 · 22").
  Widget? _cardFooter(
    StizeColors c,
    ArrivalRowStatus status,
    AppLocalizations l10n,
    String localeName,
  ) {
    final delta =
        status != ArrivalRowStatus.scheduled &&
            etaDeltaMinutes != null &&
            etaDeltaMinutes != 0
        ? _cardEtaDelta(c.onTransit)
        : null;
    Widget? later;
    if (laterEtaMinutes.isNotEmpty) {
      final far = laterEtaMinutes.any((m) => m >= kFarEtaMinutes);
      final text = far
          ? laterEtaMinutes.map((m) => clockAt(localeName, m)).join(' · ')
          // No unit: it sits right under the big ETA's "min", and a narrow
          // ETA column leaves the caption room (no "every ~20 …").
          : laterEtaMinutes.map((m) => m <= 0 ? 0 : m).join(' · ');
      later = Text(text, style: StizeTransitCard.captionStyle(c));
    }
    if (delta == null) return later;
    if (later == null) return delta;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [delta, later],
    );
  }

  /// ETA-change hint on a colour card: a white arrow + "N min" (the card's fill
  /// already carries the type colour, so the amber/green of the legacy badge
  /// would fight it — stay monochrome here).
  Widget _cardEtaDelta(Color on) {
    final later = etaDeltaMinutes! > 0;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            later ? StizeIcons.arrowUp : StizeIcons.arrowDown,
            size: 12,
            color: on.withValues(alpha: 0.8),
          ),
          Text(
            '${etaDeltaMinutes!.abs()} min',
            style: StizeType.caption.copyWith(color: on.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Legacy ListTile (flag OFF) ───────────────────
}
