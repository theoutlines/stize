import 'package:flutter/material.dart';

import '../../core/arrival_display.dart';
import '../../core/eta_format.dart';
import '../../core/movement_tracker.dart';
import '../../domain/models/arrival.dart';
import '../../l10n/app_localizations.dart';
import 'stize_transit_card.dart';

/// One arrival on a stop board, drawn as the shared [StizeTransitCard].
///
/// The card says only what helps you catch it (owner, 2026-11-25): the line,
/// where it goes, how long, where the vehicle is now and when the next ones of
/// the same direction come. Model, age and amenities live on the follow
/// screen.
class ArrivalTile extends StatelessWidget {
  const ArrivalTile({
    super.key,
    required this.arrival,
    this.onTap,
    this.destination,
    this.laterEtaMinutes = const [],
    this.stuck,
  });

  final Arrival arrival;

  /// Row tap: focus (follow) this vehicle on the map.
  final VoidCallback? onTap;

  /// The line's destination ("Ustanička"); null hides the direction row.
  final String? destination;

  /// ETAs of the later vehicles of this line×direction folded into this card.
  final List<int> laterEtaMinutes;

  /// Override for the "stopped moving" read (tests); null asks
  /// [MovementTracker.instance].
  final bool? stuck;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toString();
    final status = arrivalRowStatus(arrival);
    final live = status == ArrivalRowStatus.live;
    final isStuck =
        live && (stuck ?? MovementTracker.instance.isStuck(arrival.garageNo));

    return StizeTransitCard(
      type: arrival.vehicleType,
      line: arrival.line,
      destination: destination,
      position: _position(l10n, status),
      moving: live && !isStuck,
      etaMinutes: arrival.etaMinutes,
      scheduled: status == ArrivalRowStatus.scheduled,
      approximate: isStuck,
      next: laterLabel(l10n, localeName, laterEtaMinutes),
      live: live,
      onTap: live ? onTap : null,
    );
  }

  String? _position(AppLocalizations l10n, ArrivalRowStatus status) {
    switch (status) {
      case ArrivalRowStatus.live:
        return switch (arrivalProximity(
          stopsRemaining: arrival.stopsRemaining,
          etaMinutes: arrival.etaMinutes,
        )) {
          ArrivalProximity.here => l10n.arrivalStopsAway(0),
          ArrivalProximity.stopsAway => l10n.arrivalStopsAway(
            arrival.stopsRemaining!,
          ),
          ArrivalProximity.unknown => null,
        };
      // A garage placeholder is a vehicle waiting at the terminus: this stop is
      // where its trip begins.
      case ArrivalRowStatus.expected:
        return l10n.arrivalStartsHere;
      case ArrivalRowStatus.scheduled:
        return null;
    }
  }

  /// "next 13 · 26 · 40 min" (clock times once any is far off); null when
  /// there are none.
  static String? laterLabel(
    AppLocalizations l10n,
    String localeName,
    List<int> later,
  ) {
    if (later.isEmpty) return null;
    final far = later.any((m) => m >= kFarEtaMinutes);
    if (far) {
      return l10n
          .arrivalNextList(later.map((m) => clockAt(localeName, m)).join(' · '))
          .replaceAll(RegExp(r'\s*min$'), '');
    }
    return l10n.arrivalNextList(later.map((m) => m <= 0 ? 0 : m).join(' · '));
  }
}
