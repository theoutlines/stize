import 'package:flutter/material.dart';

import '../../core/design/stize_tokens.dart';
import '../../core/eta_format.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';

/// The one Stiže transit card (ds_stize ON): a card filled with the line's
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

  static TextStyle captionStyle(StizeColors c) =>
      StizeType.caption.copyWith(color: c.onTransit.withValues(alpha: 0.8));

  /// The small white dot marking a genuinely live vehicle in the caption.
  static Widget liveDot(StizeColors c) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: c.onTransit, shape: BoxShape.circle),
      );

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    final on = c.onTransit;
    final pad = emphasis
        ? const EdgeInsets.all(StizeSpace.space4)
        : const EdgeInsets.symmetric(
            horizontal: StizeSpace.space4, vertical: StizeSpace.space3);
    final lineStyle = (emphasis ? StizeType.h1 : StizeType.section)
        .copyWith(fontWeight: FontWeight.w600, color: on);
    final dest = destination?.trim();

    final card = Material(
      color: fillFor(c, type),
      borderRadius: BorderRadius.circular(StizeRadius.radiusCard),
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
                    Text(line, style: lineStyle),
                    if (dest != null && dest.isNotEmpty) ...[
                      const SizedBox(height: StizeSpace.space1),
                      Row(
                        children: [
                          Icon(Icons.arrow_forward_rounded, size: 16, color: on),
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
                      Wrap(
                        spacing: StizeSpace.space2,
                        runSpacing: StizeSpace.space1,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: caption,
                      ),
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
    return live ? card : Opacity(opacity: heldBackOpacity, child: card);
  }

  /// The big ETA (40/40) with its `min` unit underneath, `now` for a due
  /// vehicle, a clock time for a far-off one; a quieter clock for a timetable
  /// time.
  Widget _etaBlock(BuildContext context, StizeColors c) {
    final on = c.onTransit;
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
            fontWeight: FontWeight.w400, color: on.withValues(alpha: 0.7)),
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        value,
        if (unit != null) Text(unit, style: captionStyle(c)),
        ?etaFooter,
      ],
    );
  }
}
