import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/stize_icons.dart';
import '../../core/design/stize_tokens.dart';
import '../../core/fleet_matcher.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'fleet_badges.dart';
import 'fleet_model_card.dart';
import 'live_pulse_dot.dart';
import 'sheet_chrome.dart';
import 'stize_transit_card.dart';
import 'vehicle_icon.dart';

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
  });

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

    Widget? time;
    final m = etaMinutes;
    if (m != null) {
      final now = m <= 0;
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
          Text(
            now ? l10n.arrivalEtaNow.toLowerCase() : '$m',
            style: StizeType.bigNumber.copyWith(
              color: on,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (!now) ...[
            const SizedBox(width: StizeSpace.space1),
            Text(
              l10n.arrivalEtaMinutesUnit,
              style: StizeType.label.copyWith(color: on),
            ),
          ],
        ],
      );
      time = approximate
          ? Opacity(opacity: StizeTransitCard.approximateOpacity, child: block)
          : block;
    }

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
                const SizedBox(width: StizeSpace.space3),
                SheetCloseButton(
                  onPressed: onClose!,
                  background: Colors.black.withValues(alpha: 0.2),
                  color: on,
                ),
              ],
            ],
          ),
          const SizedBox(height: StizeSpace.space1),
          Row(
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
              ),
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
                const SizedBox(width: StizeSpace.space3 + SheetCloseButton.size),
            ],
          ),
        ],
      ),
    );
  }
}

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

  Widget _dot(StizeColors c, Color color, {bool yours = false, bool faded = false}) {
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
    final top = isFirst ? Colors.transparent : _seg(color, behind);
    final bottom = isLast
        ? Colors.transparent
        : _seg(color, behind && !vehicleBetween);
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
                        color: c.ink.withValues(alpha: subStrong ? 0.88 : 0.6),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (time != null)
            Padding(
              padding: const EdgeInsets.only(top: 10, left: StizeSpace.space3),
              child: Text(
                time,
                style: StizeType.body.copyWith(
                  fontSize: 14,
                  color: c.ink.withValues(alpha: stuck ? 0.35 : 0.7),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
    return Opacity(opacity: behind ? 0.45 : 1, child: row);
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
            top: color,
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

/// "This tram" (owner, 2026-11-25, variant A): the vehicle's photo with its
/// model and nickname over it, then short chips, one line about it, who made
/// and runs it, and the photo credit.
class FleetVehicleCard extends ConsumerWidget {
  const FleetVehicleCard({
    super.key,
    required this.fleet,
    required this.type,
    this.garageNo,
  });

  final FleetVehicle fleet;
  final VehicleType type;
  final String? garageNo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = StizeColors.of(context);
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final photo = fleet.id == null
        ? null
        : ref.watch(fleetPhotosProvider).valueOrNull?[fleet.id];
    final title = fleet.modelName ??
        (garageNo == null ? l10n.fleetUnknownModel : l10n.fleetVehicleNumber(garageNo!));
    final nick = fleet.nicknameFor(lang);
    final garage = garageNo?.trim();
    final subtitle = [
      if (nick != null) '“$nick”',
      if (garage != null && garage.isNotEmpty) '#$garage',
    ].join(' · ');

    final chips = <String>[
      if (fleetAgeYears(fleet) case final age?) l10n.fleetChipAge(age),
      if (fleet.ac != null) fleet.ac! ? l10n.fleetChipAc : l10n.fleetChipNoAc,
      if (fleet.lowFloor != null)
        fleet.lowFloor! ? l10n.fleetChipLowFloor : l10n.fleetChipSteps,
      if (fleet.articulated == true) l10n.fleetChipArticulated,
      if (fleet.capacity != null) l10n.fleetChipCapacity(fleet.capacity!),
      if (fleet.comfortScore != null)
        l10n.fleetChipComfort(
          (fleet.comfortScore! <= 2
                  ? l10n.fleetComfortRetro
                  : fleet.comfortScore == 3
                  ? l10n.fleetComfortOk
                  : l10n.fleetComfortComfy)
              .toLowerCase(),
        ),
    ];
    final note = fleet.humanNoteFor(lang);
    final made = fleet.manufacturer == null
        ? null
        : l10n.fleetMadeBy(
            fleet.country == null
                ? fleet.manufacturer!
                : '${fleet.manufacturer}, ${FleetModelView.localizedCountry(fleet.country!, lang)}',
          );
    final runBy = fleet.operatorName == null
        ? null
        : l10n.fleetOperatorShort(fleet.operatorName!);
    final credits = [?made, ?runBy].join(' · ');

    final placeholder = Container(
      color: c.fill08,
      alignment: Alignment.center,
      child: Icon(vehicleIconFor(type), size: 40, color: c.ink.withValues(alpha: 0.3)),
    );

    final hero = SizedBox(
      height: 180,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo == null)
            placeholder
          else
            Image.network(
              photo.url,
              fit: BoxFit.cover,
              semanticLabel: fleet.modelName,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : placeholder,
              errorBuilder: (context, error, stack) => placeholder,
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xA6000000)],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: StizeType.section.copyWith(color: Colors.white),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: StizeType.body.copyWith(
                          fontSize: 14,
                          height: 20 / 14,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        StizeSpace.space4,
        StizeSpace.space2,
        StizeSpace.space4,
        StizeSpace.space6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ColoredBox(
              color: c.fill06,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hero,
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (chips.isNotEmpty)
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [for (final t in chips) _chip(c, t)],
                          ),
                        if (note != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            note,
                            style: StizeType.body.copyWith(
                              fontSize: 14,
                              height: 20 / 14,
                              color: c.ink.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                        if (credits.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            credits,
                            style: StizeType.caption.copyWith(
                              color: c.ink.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (photo != null)
            InkWell(
              onTap: () => launchUrl(
                Uri.parse(photo.page),
                mode: LaunchMode.externalApplication,
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l10n.fleetPhotoShort(photo.author, photo.license),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StizeType.caption.copyWith(
                    fontSize: 11,
                    color: c.ink.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(StizeColors c, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: c.fill08,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      text,
      style: StizeType.body.copyWith(fontSize: 14, height: 20 / 14, color: c.ink),
    ),
  );
}

/// Minutes, rounded down, for a "stuck for" duration.
int stuckMinutesOf(Duration d) => d.inMinutes < 1 ? 1 : d.inMinutes;
