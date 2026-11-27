import 'package:flutter/material.dart';

import '../../core/design/stize_tokens.dart';
import '../../core/eta_format.dart';
import '../../l10n/app_localizations.dart';

/// The big live arrival time, the one component every transit card and the
/// follow card draw (design system: ArrivalRow, "Time"):
///
///  * 40/40 medium tabular, "min" beside it on one baseline (16/24 medium);
///  * "now" for a due vehicle, a 24h clock time from [kFarEtaMinutes] on,
///    "—" when unknown;
///  * a vehicle that stopped moving ([approximate]): "≈" before the time and
///    the whole block at [approximateOpacity];
///  * a changed time swaps softly (150 ms, 4 px) instead of jumping.
///
/// Drawn on a transit colour, so everything is in [color] (the on-transit
/// colour of the card).
class ArrivalTime extends StatelessWidget {
  const ArrivalTime({
    super.key,
    required this.etaMinutes,
    required this.color,
    this.approximate = false,
  });

  final int? etaMinutes;
  final Color color;
  final bool approximate;

  /// Opacity of a time we no longer trust.
  static const double approximateOpacity = 0.5;

  @override
  Widget build(BuildContext context) {
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
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

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
              color: color,
            ),
          ),
          const SizedBox(width: 2),
        ],
        swapped,
        if (unit != null) ...[
          const SizedBox(width: StizeSpace.space1),
          Text(unit, style: StizeType.label.copyWith(color: color)),
        ],
      ],
    );
    return approximate
        ? Opacity(opacity: approximateOpacity, child: block)
        : block;
  }
}
