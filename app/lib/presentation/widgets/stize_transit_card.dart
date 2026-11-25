import 'package:flutter/material.dart';

import 'flat_cards.dart';
import 'live_pulse_dot.dart';
import 'vehicle_icon.dart';

import '../../core/design/stize_tokens.dart';
import '../../core/eta_format.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import '../../core/design/stize_icons.dart';

/// The one Stiže transit card. Every list that shows "a line arriving" draws
/// THIS widget (stop board, Nearby, the timetable section), so the cards can't
/// drift apart.
///
/// Live layout (owner, 2026-11-25, variant 10), a two-column grid:
///
///     [7L plate]                 3 min     ← row 1, centred
///     → Ustanička        • 1 stop away     ← row 2, one baseline
///     (stop · 143 m)   next 13 · 26 min    ← row 3, optional
///
/// The line number sits on a white plate in the line colour. The position
/// caption carries a dot that breathes while the vehicle moves; a vehicle that
/// stopped moving loses the dot and its time dims with an "≈".
///
/// A timetable card ([scheduled]) is neutral with a coloured plate, a quiet
/// clock time and its two follow-ups under it.
class StizeTransitCard extends StatelessWidget {
  const StizeTransitCard({
    super.key,
    required this.type,
    required this.line,
    this.destination,
    this.position,
    this.moving = false,
    this.etaMinutes,
    this.scheduled = false,
    this.approximate = false,
    this.next,
    this.leftNote,
    this.followUps,
    this.live = true,
    this.topInset = 0,
    this.onTap,
  });

  final VehicleType type;
  final String line;
  final String? destination;

  /// Where the vehicle is, right under the time ("1 stop away", "Starts
  /// here"). Null leaves the slot empty.
  final String? position;

  /// The vehicle is moving: a pulsing dot leads [position].
  final bool moving;

  /// Minutes to the arrival the card is about; null shows a dash.
  final int? etaMinutes;

  /// A timetable time (no vehicle yet): a neutral card with a clock time.
  final bool scheduled;

  /// The time is an estimate we no longer trust (the vehicle stopped
  /// reporting motion): dimmed, with "≈".
  final bool approximate;

  /// The later vehicles of this line and direction ("next 13 · 26 min").
  final String? next;

  /// Optional line under the destination (Nearby: "Lion · 143 m").
  final String? leftNote;

  /// Timetable card only: the follow-up clock times ("11:05 · 11:08").
  final String? followUps;

  /// Leads to a live vehicle you can follow: full brightness. Otherwise held
  /// back so the tappable cards read first.
  final bool live;

  /// Extra room above row 1 (a Nearby carousel keeps its page dots there).
  final double topInset;

  final VoidCallback? onTap;

  static const double heldBackOpacity = 0.82;

  /// Opacity of a time we no longer trust.
  static const double approximateOpacity = 0.5;

  /// The card's surface as it reads on screen (a held-back card included), for
  /// a list that stretches its first or last card past the edge.
  static Color surfaceFor(
    StizeColors c,
    VehicleType type, {
    required bool scheduled,
    required bool live,
  }) {
    final fill = scheduled ? c.fill08 : fillFor(c, type);
    if (live || scheduled) return fill;
    return fill.withValues(alpha: fill.a * heldBackOpacity);
  }

  static Color fillFor(StizeColors c, VehicleType type) => switch (type) {
    VehicleType.bus => c.transitBus,
    VehicleType.tram => c.transitTram,
    VehicleType.trolleybus => c.transitTrolleybus,
  };

  /// Text/icon colour on the card: white on a live colour fill, the theme ink on
  /// a timetable card.
  static Color onFor(StizeColors c, bool scheduled) =>
      scheduled ? c.ink : c.onTransit;

  /// The position / note caption (12/16).
  static TextStyle captionStyle(StizeColors c, {bool scheduled = false}) =>
      StizeType.caption.copyWith(
        color: onFor(c, scheduled).withValues(alpha: scheduled ? 0.8 : 0.88),
      );

  /// The line number on its plate, led by the vehicle type's icon (owner,
  /// 2026-11-25, variant A: colour alone doesn't tell a visitor tram from
  /// bus). White plate + line colour on a live card; line-colour plate +
  /// white on a timetable card.
  static Widget plate(
    StizeColors c,
    VehicleType type,
    String line, {
    bool inverted = false,
  }) {
    final fill = fillFor(c, type);
    final ink = inverted ? c.onTransit : fill;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
      decoration: BoxDecoration(
        color: inverted ? fill : c.onTransit,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(vehicleIconFor(type), size: 18, color: ink),
          const SizedBox(width: 4),
          Text(
            line,
            // White on a colour plate reads heavier than colour on white:
            // the timetable plate drops to 500 so both look the same weight
            // (owner, 2026-11-25).
            style: StizeType.section.copyWith(
              fontWeight: inverted ? FontWeight.w500 : FontWeight.w600,
              height: 1.2,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    final on = onFor(c, scheduled);
    final dest = destination?.trim();
    final flat = FlatCards.of(context);

    final row1 = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        plate(c, type, line, inverted: scheduled),
        const SizedBox(width: StizeSpace.space3),
        const Spacer(),
        scheduled ? _clock(context, c) : _eta(context, c),
      ],
    );

    final rightCaption = scheduled
        ? (followUps == null
              ? null
              : Text(followUps!, style: captionStyle(c, scheduled: true)))
        : _position(c);

    final row2 = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: dest == null || dest.isEmpty
              ? const SizedBox.shrink()
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    // Baseline-aligned, an icon sits on its bottom edge and reads
                    // high: drop it 3px onto the text's x-height centre.
                    Transform.translate(
                      offset: const Offset(0, 3),
                      child: Icon(StizeIcons.forward, size: 16, color: on),
                    ),
                    const SizedBox(width: StizeSpace.space1),
                    Flexible(
                      child: Text(
                        dest,
                        style: StizeType.label.copyWith(color: on),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
        if (rightCaption != null) ...[
          const SizedBox(width: StizeSpace.space3),
          rightCaption,
        ],
      ],
    );

    final hasNext = next != null && !scheduled;
    final hasRow3 = leftNote != null || hasNext;
    // One fixed 24px line, 6px below the destination row, whatever it holds:
    // the stop line of a Nearby card sits in the same place with or without a
    // "next" beside it, so neighbouring cards line up (owner, 2026-11-25).
    final row3 = !hasRow3
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SizedBox(
              height: 24,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: leftNote == null
                        ? const SizedBox.shrink()
                        : Text(
                            leftNote!,
                            style: captionStyle(c, scheduled: scheduled),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  if (hasNext) ...[
                    const SizedBox(width: StizeSpace.space3),
                    Text(
                      next!,
                      style: StizeType.lineNumber.copyWith(color: on),
                    ),
                  ],
                ],
              ),
            ),
          );

    final card = Material(
      color: scheduled ? c.fill08 : fillFor(c, type),
      // Edge-to-edge in the sheet and the desktop island: square, a hairline
      // below.
      borderRadius: flat ? null : BorderRadius.circular(StizeRadius.radiusCard),
      shape: flat ? Border(bottom: BorderSide(color: c.stripeLine)) : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            StizeSpace.space4,
            StizeSpace.space3 + topInset,
            StizeSpace.space4,
            StizeSpace.space3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              row1,
              const SizedBox(height: StizeSpace.space1),
              row2,
              if (row3 != null) ...[
                const SizedBox(height: StizeSpace.space1),
                row3,
              ],
            ],
          ),
        ),
      ),
    );
    return live || scheduled
        ? card
        : Opacity(opacity: heldBackOpacity, child: card);
  }

  Widget? _position(StizeColors c) {
    if (position == null) return null;
    final style = captionStyle(c);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (moving) ...[
          LivePulseDot(color: c.onTransit),
          const SizedBox(width: StizeSpace.space1),
        ],
        Text(position!, style: style, maxLines: 1),
      ],
    );
  }

  /// The timetable clock time: 24 Regular at 70%.
  Widget _clock(BuildContext context, StizeColors c) {
    final localeName = Localizations.localeOf(context).toString();
    final m = etaMinutes;
    return Text(
      m == null ? '—' : clockAt(localeName, m),
      style: StizeType.date.copyWith(
        fontWeight: FontWeight.w400,
        color: c.ink.withValues(alpha: 0.7),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  /// The big live time: 40 with "min" beside it on one baseline; "now" for a
  /// due vehicle; a clock time for a far one.
  Widget _eta(BuildContext context, StizeColors c) {
    final on = c.onTransit;
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final m = etaMinutes;

    final String text;
    String? unit;
    if (m == null) {
      text = '—';
    } else if (m <= 0) {
      text = l10n.arrivalEtaNow.toLowerCase(); // "now", not "0"
    } else if (m >= kFarEtaMinutes) {
      text = clockAt(localeName, m);
    } else {
      text = '$m';
      unit = l10n.arrivalEtaMinutesUnit;
    }

    final value = Text(
      text,
      key: ValueKey(text),
      style: StizeType.bigNumber.copyWith(
        color: on,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    // A changed time swaps softly (150ms, 4px) instead of jumping.
    final swapped = AnimatedSwitcher(
      duration: StizeMotion.quick,
      switchInCurve: StizeMotion.inOut,
      switchOutCurve: StizeMotion.inOut,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerRight,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.1),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: value,
    );

    final block = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (approximate) ...[
          Text(
            '≈',
            style: StizeType.h1.copyWith(
              fontWeight: FontWeight.w400,
              height: 1,
              color: on,
            ),
          ),
          const SizedBox(width: 2),
        ],
        swapped,
        if (unit != null) ...[
          const SizedBox(width: StizeSpace.space1),
          Text(unit, style: StizeType.label.copyWith(color: on)),
        ],
      ],
    );
    return approximate
        ? Opacity(opacity: approximateOpacity, child: block)
        : block;
  }
}
