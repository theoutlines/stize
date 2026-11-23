import 'package:flutter/material.dart';

import 'flat_cards.dart';

import '../../core/design/stize_tokens.dart';
import '../../core/eta_format.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import '../../core/design/stize_icons.dart';

/// The one Stiže transit card: a card filled with the line's
/// transit colour, white content. Every list that shows "a line arriving"
/// draws THIS widget (stop board, Nearby, scheduled groups), so the cards can't
/// drift apart: same paddings, type, ETA block and dimming rule.
///
/// Layout: line number (the one semibold) / "→ destination" / a caption row on
/// the left; the ETA block on the right. A card that doesn't lead to a live,
/// followable vehicle is held back (opacity [heldBackOpacity]).
class StizeTransitCard extends StatelessWidget {
  const StizeTransitCard({
    super.key,
    required this.type,
    required this.line,
    this.destination,
    this.caption = const [],
    this.etaMinutes,
    this.scheduled = false,
    this.etaFooter,
    this.live = true,
    this.emphasis = false,
    this.onTap,
  });

  final VehicleType type;
  final String line;
  final String? destination;

  /// Caption pieces (12/16, white 80%), laid out in a wrapping row. Build text
  /// pieces with [captionStyle]; [liveDot] marks a live vehicle.
  final List<Widget> caption;

  /// Minutes to the arrival the card is about; null shows a dash.
  final int? etaMinutes;

  /// A timetable time (no vehicle yet): the ETA shows as a quieter clock time,
  /// never a count.
  final bool scheduled;

  /// Optional line under the ETA (ETA-change hint, follow-up clock times).
  final Widget? etaFooter;

  /// Leads to a live vehicle you can follow: full brightness. Otherwise held
  /// back so the tappable cards read first.
  final bool live;

  /// The first card on a stop board: bigger line number and padding.
  final bool emphasis;

  final VoidCallback? onTap;

  static const double heldBackOpacity = 0.82;

  static Color fillFor(StizeColors c, VehicleType type) => switch (type) {
    VehicleType.bus => c.transitBus,
    VehicleType.tram => c.transitTram,
    VehicleType.trolleybus => c.transitTrolleybus,
  };

  /// Text/icon colour on the card: white on a live colour fill, the theme ink on
  /// a scheduled card (neutral surface, only the line number carries colour).
  static Color onFor(StizeColors c, bool scheduled) =>
      scheduled ? c.ink : c.onTransit;

  static TextStyle captionStyle(StizeColors c, {bool scheduled = false}) =>
      StizeType.caption.copyWith(
        color: onFor(c, scheduled).withValues(alpha: 0.8),
      );

  /// The small white dot marking a genuinely live vehicle in the caption.
  static Widget liveDot(StizeColors c) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(color: c.onTransit, shape: BoxShape.circle),
  );

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    final on = onFor(c, scheduled);
    // One size for every card in every list (owner, 2026-11-23: the bigger
    // first card read as a different component). `emphasis` is kept for
    // callers but no longer changes the card.
    const pad = EdgeInsets.symmetric(
      horizontal: StizeSpace.space4,
      vertical: StizeSpace.space3,
    );
    final lineStyle = StizeType.section.copyWith(
      fontWeight: FontWeight.w600,
      color: on,
    );
    final dest = destination?.trim();

    final flat = FlatCards.of(context);
    final card = Material(
      // A timetable time is a neutral card with a coloured line badge: a dimmed
      // colour fill read as muddy navy / brown next to the live cards.
      color: scheduled ? c.fill08 : fillFor(c, type),
      // Edge-to-edge in the mobile sheet: square, a hairline below.
      borderRadius: flat ? null : BorderRadius.circular(StizeRadius.radiusCard),
      shape: flat
          ? const Border(bottom: BorderSide(color: Color(0x2E000000)))
          : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: pad,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (scheduled)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: StizeSpace.space2,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: fillFor(c, type),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          line,
                          style: lineStyle.copyWith(color: c.onTransit),
                        ),
                      )
                    else
                      Text(line, style: lineStyle),
                    if (dest != null && dest.isNotEmpty) ...[
                      const SizedBox(height: StizeSpace.space1),
                      Row(
                        children: [
                          Icon(StizeIcons.forward, size: 16, color: on),
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
                    ],
                    if (caption.isNotEmpty) ...[
                      const SizedBox(height: StizeSpace.space1),
                      _captionRow(),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: StizeSpace.space3),
              _etaBlock(context, c),
            ],
          ),
        ),
      ),
    );
    return live || scheduled
        ? card
        : Opacity(opacity: heldBackOpacity, child: card);
  }

  /// One caption line, never wrapped: on a narrow card the texts shorten with an
  /// ellipsis, while the live dot and the fleet badges keep their size and stay
  /// on the same line (a wrapped badge row read as a stray, indented line).
  Widget _captionRow() {
    final children = <Widget>[];
    for (final w in caption) {
      if (children.isNotEmpty)
        children.add(const SizedBox(width: StizeSpace.space2));
      if (w is Text && w.data != null) {
        children.add(
          Flexible(
            child: Text(
              w.data!,
              style: w.style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        );
      } else {
        children.add(w);
      }
    }
    return Row(children: children);
  }

  /// The big ETA (40/40) with its `min` unit underneath, `now` for a due
  /// vehicle, a clock time for a far-off one; a quieter clock for a timetable
  /// time.
  Widget _etaBlock(BuildContext context, StizeColors c) {
    final on = onFor(c, scheduled);
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final m = etaMinutes;

    Widget value;
    String? unit;
    if (m == null) {
      value = Text('—', style: StizeType.bigNumber.copyWith(color: on));
    } else if (scheduled) {
      value = Text(
        clockAt(localeName, m),
        style: StizeType.date.copyWith(
          fontWeight: FontWeight.w400,
          color: on.withValues(alpha: 0.7),
        ),
      );
    } else {
      final String text;
      if (m <= 0) {
        text = l10n.arrivalEtaNow.toLowerCase(); // "now", not "0"
      } else if (m >= kFarEtaMinutes) {
        text = clockAt(localeName, m);
      } else {
        text = '$m';
        unit = l10n.arrivalEtaMinutesUnit;
      }
      value = Text(text, style: StizeType.bigNumber.copyWith(color: on));
    }

    // A changed ETA swaps softly (text swap: 150ms, 4px, in-out) instead of
    // jumping (owner, 2026-11-23).
    final keyed = KeyedSubtree(
      key: ValueKey(value is Text ? value.data : m),
      child: value,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSwitcher(
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
          child: keyed,
        ),
        if (unit != null)
          Text(unit, style: captionStyle(c, scheduled: scheduled)),
        ?etaFooter,
      ],
    );
  }
}
