import 'package:flutter/material.dart';

import '../../core/design/stize_tokens.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import 'arrival_time.dart';
import 'live_pulse_dot.dart';
import 'sheet_chrome.dart';
import 'stize_transit_card.dart';

/// One vehicle of the followed line and direction in the head's switcher.
class FollowVehicleOption {
  const FollowVehicleOption({
    required this.etaMinutes,
    required this.selected,
    required this.onTap,
  });

  final int etaMinutes;
  final bool selected;
  final VoidCallback onTap;
}

/// The head of the follow sheet: the followed vehicle as a card in its line
/// colour, the same grid as a stop-board card (owner, 2026-11-25).
///
///     [7L plate]              3 min  (×)   ← × only where the close lives
///     → Ustanička   2 stops to Batutova       inside (desktop island)
///
/// On mobile the card is the top of the sheet: it carries the drag handle and
/// the sheet's top corners; the close button rides outside, above the sheet.
class FollowHeader extends StatelessWidget {
  const FollowHeader({
    super.key,
    required this.line,
    required this.type,
    this.destination,
    this.etaMinutes,
    this.caption,
    this.moving = false,
    this.approximate = false,
    this.onClose,
    this.showHandle = false,
    this.topRadius = 0,
    this.vehicles = const [],
  });

  /// The vehicles of this line and direction on your stop's board ("1 · 3 ·
  /// 7 min"), the followed one picked; a tap follows that one instead
  /// (owner, 2026-11-25, S1). Fewer than two: no switcher.
  final List<FollowVehicleOption> vehicles;

  final String line;
  final VehicleType type;
  final String? destination;

  /// Minutes to your stop (or to the next stop when there is no "your stop").
  final int? etaMinutes;

  /// "2 stops to Batutova" / "Next: Pop Stojanova".
  final String? caption;

  /// The vehicle is moving: a pulsing dot leads the caption.
  final bool moving;

  /// The vehicle stopped reporting motion: time dimmed with "≈".
  final bool approximate;

  /// Close inside the card (desktop island). Null: no close here.
  final VoidCallback? onClose;

  /// Mobile sheet: the card carries the sheet's grabber.
  final bool showHandle;
  final double topRadius;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    final l10n = AppLocalizations.of(context);
    final on = c.onTransit;
    final fill = StizeTransitCard.fillFor(c, type);

    final Widget? time = etaMinutes == null
        ? null
        : ArrivalTime(
            etaMinutes: etaMinutes,
            color: on,
            approximate: approximate,
          );

    final dest = destination?.trim();
    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
      ),
      padding: EdgeInsets.fromLTRB(
        StizeSpace.space4,
        showHandle ? 0 : StizeSpace.space3,
        StizeSpace.space4,
        StizeSpace.space3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHandle)
            Center(child: SheetDragHandle(color: on.withValues(alpha: 0.5))),
          Row(
            children: [
              StizeTransitCard.plate(c, type, line),
              const Spacer(),
              ?time,
              if (onClose != null) ...[
                const SizedBox(
                  width: StizeSpace.space3 - SheetCloseButton.inset,
                ),
                // The circle sits flush with the card's content edge, like the
                // times in the lists below (owner, 2026-11-26).
                Transform.translate(
                  offset: const Offset(SheetCloseButton.inset, 0),
                  child: SheetCloseButton(
                    onPressed: onClose!,
                    background: Colors.black.withValues(alpha: 0.2),
                    color: on,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: StizeSpace.space1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: StizeTransitCard.destinationLine(dest, on)),
              if (caption != null) ...[
                const SizedBox(width: StizeSpace.space3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (moving) ...[
                      LivePulseDot(color: on),
                      const SizedBox(width: StizeSpace.space1),
                    ],
                    Text(
                      caption!,
                      style: StizeTransitCard.captionStyle(c),
                      maxLines: 1,
                    ),
                  ],
                ),
              ],
              // Keeps the caption flush with the time above it when the close
              // sits in the first row.
              if (onClose != null)
                const SizedBox(
                  width:
                      StizeSpace.space3 +
                      SheetCloseButton.size -
                      2 * SheetCloseButton.inset,
                ),
            ],
          ),
          if (vehicles.length > 1) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(
                  right: onClose != null
                      ? StizeSpace.space3 +
                            SheetCloseButton.size -
                            2 * SheetCloseButton.inset
                      : 0,
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 6,
                  children: [
                    for (final v in vehicles) _segment(c, l10n, fill, v),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _segment(
    StizeColors c,
    AppLocalizations l10n,
    Color fill,
    FollowVehicleOption v,
  ) {
    final label = v.etaMinutes <= 0
        ? l10n.arrivalEtaNow.toLowerCase()
        : '${v.etaMinutes} ${l10n.arrivalEtaMinutesUnit}';
    return Semantics(
      button: true,
      selected: v.selected,
      child: Material(
        color: v.selected ? c.onTransit : Colors.black.withValues(alpha: 0.18),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: v.selected ? null : v.onTap,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            // Shrink-wrapped: an aligned Container would stretch to the row.
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: StizeType.lineNumber.copyWith(
                  height: 1.2,
                  color: v.selected ? fill : c.onTransit,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
