import 'package:flutter/material.dart';

import '../../core/arrival_display.dart';
import '../../core/design/stize_tokens.dart';
import '../../core/eta_format.dart';
import '../../core/fleet_matcher.dart';
import '../../core/map_support.dart';
import '../../domain/models/arrival.dart';
import '../../l10n/app_localizations.dart';
import 'fleet_badges.dart';
import 'stize_transit_card.dart';
import 'vehicle_icon.dart';

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

  /// Opacity for a non-clickable row (Expected / Scheduled). Brightness is the
  /// single, at-a-glance signal for "can I tap this?" — dim == not tappable.
  static const double _dimOpacity = 0.58;

  @override
  Widget build(BuildContext context) {
    // The Stiže design system is behind the `ds_stize` flag: when its colour
    // extension is present (flag ON), draw the filled transit card; when it is
    // absent (OFF), keep the previous ListTile exactly as it was (killswitch).
    final stize = Theme.of(context).extension<StizeColors>();
    if (stize == null) return _legacy(context);
    return _card(context, stize);
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
      caption: _caption(context, c, c.onTransit, status, live, l10n, localeName),
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
    final style = StizeTransitCard.captionStyle(c);

    // Primary descriptor: stops-away for a live row, the honest status word for
    // the rest. `arrivalProximity` guards the junk `stops_remaining = 0`.
    String? primary;
    if (live) {
      primary = switch (arrivalProximity(
        stopsRemaining: arrival.stopsRemaining,
        etaMinutes: arrival.etaMinutes,
      )) {
        ArrivalProximity.here => l10n.arrivalStopsAway(0),
        ArrivalProximity.stopsAway => l10n.arrivalStopsAway(arrival.stopsRemaining!),
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
      if (every != null) Text(every, style: style),
      ?strip,
    ];
    return parts;
  }

  /// Under the big ETA: the ETA-change hint (G1) and the later trips of this
  /// direction folded into the card ("7 · 22 min").
  Widget? _cardFooter(
    StizeColors c,
    ArrivalRowStatus status,
    AppLocalizations l10n,
    String localeName,
  ) {
    final delta = status != ArrivalRowStatus.scheduled &&
            etaDeltaMinutes != null &&
            etaDeltaMinutes != 0
        ? _cardEtaDelta(c.onTransit)
        : null;
    Widget? later;
    if (laterEtaMinutes.isNotEmpty) {
      final far = laterEtaMinutes.any((m) => m >= kFarEtaMinutes);
      final text = far
          ? laterEtaMinutes.map((m) => clockAt(localeName, m)).join(' · ')
          : '${laterEtaMinutes.map((m) => m <= 0 ? 0 : m).join(' · ')} ${l10n.arrivalEtaMinutesUnit}';
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
            later ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
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

  Widget _legacy(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final status = arrivalRowStatus(arrival);
    // Clickability == live. A dimmed row + missing chevron means "not a vehicle
    // you can follow" (Expected placeholder / Scheduled fallback) without the
    // user having to read the subtitle to find out.
    final clickable = status == ArrivalRowStatus.live;
    final dim = clickable ? 1.0 : _dimOpacity;

    return ListTile(
      onTap: onTap,
      // Match the map's transport palette so a line reads the same colour here
      // as its marker on the map (bus blue, trolley orange, tram red).
      leading: Opacity(
        opacity: dim,
        child: CircleAvatar(
          backgroundColor: vehicleColor(arrival.vehicleType),
          child: vehicleGlyph(
            arrival.vehicleType,
            size: 22,
            color: Colors.white,
          ),
        ),
      ),
      title: Opacity(
        opacity: dim,
        child: Text(arrival.line, style: theme.textTheme.titleMedium),
      ),
      subtitle: _legacySubtitle(context, l10n, status),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: dim,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  etaLabel(l10n, Localizations.localeOf(context).toString(),
                      arrival.etaMinutes),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (etaDeltaMinutes != null && etaDeltaMinutes != 0)
                  _EtaChangeBadge(deltaMinutes: etaDeltaMinutes!),
              ],
            ),
          ),
          // The chevron is the drill-in affordance: only a live vehicle can be
          // opened and followed on the map.
          if (clickable)
            Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }

  /// Second line of the tile: the "N stops away" text and the Fleet-ID badge
  /// strip, kept on a single row so a badge never turns one row into two (B2).
  Widget? _legacySubtitle(BuildContext context, AppLocalizations l10n, ArrivalRowStatus status) {
    final theme = Theme.of(context);
    // A clock + honest status label, so no row renders blank and none pretends
    // to be a tappable live vehicle:
    //   * Scheduled → "Scheduled" (timetable fallback, no vehicle at all).
    //   * Expected  → "Expected"  (valid ETA, no live position yet — the
    //                 placeholder class; reclassification is arrivals-dedup's).
    // The clock keeps its normal muted colour ("as now"); the row-level dimming
    // is applied to the line icon + ETA in build().
    final Widget? statusChip;
    if (status == ArrivalRowStatus.scheduled || status == ArrivalRowStatus.expected) {
      statusChip = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            status == ArrivalRowStatus.scheduled ? l10n.arrivalScheduled : l10n.arrivalExpected,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      );
    } else {
      // Live: describe proximity, but don't trust stops_remaining blindly — the
      // upstream emits 0 as junk for some rows even with a 10-20 min ETA, so
      // "here" would lie. Only show it when it agrees with the ETA.
      final stopsText = switch (arrivalProximity(
        stopsRemaining: arrival.stopsRemaining,
        etaMinutes: arrival.etaMinutes,
      )) {
        ArrivalProximity.here => l10n.arrivalStopsAway(0),
        ArrivalProximity.stopsAway => l10n.arrivalStopsAway(arrival.stopsRemaining!),
        ArrivalProximity.unknown => null,
      };
      statusChip = stopsText == null
          ? null
          : Flexible(child: Text(stopsText, overflow: TextOverflow.ellipsis));
    }
    // Fleet badges belong to a vehicle identified by garage number — present for
    // both live AND expected (placeholder) rows, but never for a scheduled row
    // (no vehicle exists yet), matching the prior behaviour for scheduled.
    final strip = (fleet == null || status == ArrivalRowStatus.scheduled)
        ? null
        : FleetBadgeStrip(
            fleet: fleet!,
            garageNo: arrival.garageNo,
            onTap: fleet!.hasInfo ? onOpenFleetCard : null,
          );
    if (statusChip == null && strip == null) return null;
    return Row(
      children: [
        if (statusChip != null) statusChip,
        if (statusChip != null && strip != null) const SizedBox(width: 10),
        ?strip,
      ],
    );
  }
}

/// Compact "+N / −N min" badge with an up/down arrow. Later (delayed) reads
/// amber; sooner reads green. The number is language-neutral, so no extra
/// localisation is needed for the glanceable form. (Legacy / flag-OFF path.)
class _EtaChangeBadge extends StatelessWidget {
  const _EtaChangeBadge({required this.deltaMinutes});

  final int deltaMinutes;

  @override
  Widget build(BuildContext context) {
    final later = deltaMinutes > 0;
    final color = later ? const Color(0xFFB25A00) : const Color(0xFF1E7A46);
    final bg = color.withValues(alpha: 0.14);
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            later ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 1),
          Text(
            '${deltaMinutes.abs()} min',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
