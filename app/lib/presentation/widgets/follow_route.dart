import 'package:flutter/material.dart';

import '../../core/design/stize_tokens.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import 'stize_transit_card.dart';

/// One stop on the followed vehicle's route.
class FollowRouteStop {
  const FollowRouteStop({
    required this.name,
    this.etaMinutes,
    this.passed = false,
    this.yours = false,
    this.vehicleHere = false,
  });

  final String name;
  final int? etaMinutes;
  final bool passed;
  final bool yours;

  /// The vehicle stands at this stop: its marker replaces the stop's dot.
  final bool vehicleHere;
}

/// The route as the map draws it: a vertical line in the line colour with
/// round stop dots, the vehicle's marker on it, the stop behind dimmed and your
/// stop highlighted. Each row is aligned to its dot by the first text line.
///
/// When the vehicle stopped reporting motion ([stuckMinutes]) its row says so
/// and every time after it dims with "≈".
class FollowRoute extends StatelessWidget {
  const FollowRoute({
    super.key,
    required this.stops,
    required this.line,
    required this.type,
    this.vehicleBetween = false,
    this.stuckMinutes,
  });

  /// Passed stop (optional) first, then the stops ahead.
  final List<FollowRouteStop> stops;
  final String line;
  final VehicleType type;

  /// The vehicle is on the way between the passed stop and the next one: its
  /// marker sits on the line between them.
  final bool vehicleBetween;

  /// Minutes the vehicle has not moved, once it reads as stuck; null = moving.
  final int? stuckMinutes;

  static const double _railW = 32;
  static const double _lineW = 4;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    final l10n = AppLocalizations.of(context);
    final color = StizeTransitCard.fillFor(c, type);
    final stuck = stuckMinutes != null;

    final rows = <Widget>[];
    for (var i = 0; i < stops.length; i++) {
      final s = stops[i];
      final isFirst = i == 0;
      final isLast = i == stops.length - 1 && !(vehicleBetween && s.passed);
      rows.add(_stopRow(context, c, l10n, color, s, isFirst, isLast, stuck));
      if (vehicleBetween && s.passed) {
        rows.add(_vehicleRow(c, l10n, color, stuck));
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        StizeSpace.space4,
        StizeSpace.space2,
        StizeSpace.space4,
        StizeSpace.space2,
      ),
      child: Column(children: rows),
    );
  }

  /// Rail segment colours: full line colour ahead, faded behind the vehicle.
  Color _seg(Color color, bool behind) =>
      behind ? color.withValues(alpha: 0.35) : color;

  Widget _rail({
    required Color top,
    required Color bottom,
    required Widget dot,
    double dotCenter = 22,
  }) {
    return SizedBox(
      width: _railW,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: (_railW - _lineW) / 2,
            top: 0,
            height: dotCenter,
            width: _lineW,
            child: ColoredBox(color: top),
          ),
          Positioned(
            left: (_railW - _lineW) / 2,
            top: dotCenter,
            bottom: 0,
            width: _lineW,
            child: ColoredBox(color: bottom),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: dotCenter - 14,
            height: 28,
            child: Center(child: dot),
          ),
        ],
      ),
    );
  }

  Widget _marker(StizeColors c, Color color) => Container(
    width: 28,
    height: 28,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: c.sheet, width: 3),
    ),
    child: FittedBox(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Text(
          line,
          style: StizeType.control.copyWith(
            fontWeight: FontWeight.w600,
            color: c.onTransit,
          ),
        ),
      ),
    ),
  );

  Widget _dot(
    StizeColors c,
    Color color, {
    bool yours = false,
    bool faded = false,
  }) {
    final ring = faded ? color.withValues(alpha: 0.35) : color;
    return Container(
      width: yours ? 16 : 12,
      height: yours ? 16 : 12,
      decoration: BoxDecoration(
        color: yours ? c.onTransit : c.sheet,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: yours ? 4 : 3),
      ),
    );
  }

  Widget _stopRow(
    BuildContext context,
    StizeColors c,
    AppLocalizations l10n,
    Color color,
    FollowRouteStop s,
    bool isFirst,
    bool isLast,
    bool stuck,
  ) {
    final behind = s.passed;
    // The line behind the vehicle (into the stop it stands at, or up to its
    // marker between stops) is faded; ahead of it, full colour.
    final top = isFirst
        ? Colors.transparent
        : _seg(color, behind || s.vehicleHere);
    final bottom = isLast ? Colors.transparent : _seg(color, behind);
    final dot = s.vehicleHere
        ? _marker(c, color)
        : _dot(c, color, yours: s.yours, faded: behind);

    String? sub;
    var subStrong = false;
    if (s.yours) sub = l10n.followYourStop;
    if (s.vehicleHere && stuck) {
      sub = l10n.followStuck(stuckMinutes!);
      subStrong = true;
    }

    final afterVehicle = !behind && !s.vehicleHere;
    String? time;
    final eta = s.etaMinutes;
    if (!behind && eta != null && !(s.vehicleHere && stuck)) {
      final t = eta <= 0
          ? l10n.arrivalEtaNow.toLowerCase()
          : '$eta ${l10n.arrivalEtaMinutesUnit}';
      time = stuck && afterVehicle ? '≈ $t' : t;
    }

    final row = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _rail(top: top, bottom: bottom, dot: dot),
          const SizedBox(width: StizeSpace.space3),
          Expanded(
            child: Opacity(
              // The stop behind: its words dim, the rail keeps its own shade.
              opacity: behind ? 0.45 : 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (s.yours ? StizeType.lineNumber : StizeType.body)
                          .copyWith(color: c.ink),
                    ),
                    if (sub != null)
                      Text(
                        sub,
                        style: StizeType.caption.copyWith(
                          fontWeight: subStrong ? FontWeight.w500 : null,
                          color: c.ink.withValues(
                            alpha: subStrong ? 0.88 : 0.6,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (time != null)
            Padding(
              padding: const EdgeInsets.only(top: 10, left: StizeSpace.space3),
              child: Text(
                time,
                // DS: `body` 16/24 (14 is off the type scale).
                style: StizeType.body.copyWith(
                  color: c.ink.withValues(alpha: stuck ? 0.35 : 0.7),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
    return row;
  }

  /// The vehicle between two stops: its marker on the line, and the stuck
  /// note when it stopped moving.
  Widget _vehicleRow(
    StizeColors c,
    AppLocalizations l10n,
    Color color,
    bool stuck,
  ) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _rail(
            top: _seg(color, true),
            bottom: color,
            dot: _marker(c, color),
            dotCenter: 18,
          ),
          const SizedBox(width: StizeSpace.space3),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: stuck
                    ? Text(
                        l10n.followStuck(stuckMinutes!),
                        style: StizeType.caption.copyWith(
                          fontWeight: FontWeight.w500,
                          color: c.ink.withValues(alpha: 0.88),
                        ),
                      )
                    : const SizedBox(height: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minutes, rounded down, for a "stuck for" duration.
int stuckMinutesOf(Duration d) => d.inMinutes < 1 ? 1 : d.inMinutes;
