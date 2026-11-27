import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/stize_tokens.dart';
import '../../core/fleet_matcher.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'fleet_badges.dart';
import '../../core/fleet_country.dart';
import 'vehicle_icon.dart';

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
    final title =
        fleet.modelName ??
        (garageNo == null
            ? l10n.fleetUnknownModel
            : l10n.fleetVehicleNumber(garageNo!));
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
                : '${fleet.manufacturer}, ${localizedFleetCountry(fleet.country!, lang)}',
          );
    final runBy = fleet.operatorName == null
        ? null
        : l10n.fleetOperatorShort(fleet.operatorName!);
    final credits = [?made, ?runBy].join(' · ');

    final placeholder = Container(
      color: c.fill08,
      alignment: Alignment.center,
      child: Icon(
        vehicleIconFor(type),
        size: 40,
        color: c.ink.withValues(alpha: 0.3),
      ),
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
                        // DS: `caption` 12/16 under the model name.
                        style: StizeType.caption.copyWith(
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
                            // DS: `body` 16/24.
                            style: StizeType.body.copyWith(
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
                  // DS: `note` 12/16 in ink-50 (11 is off the scale).
                  style: StizeType.note.copyWith(color: c.ink50),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(StizeColors c, String text) => Container(
    // DS Chip: `control` 12/16 on `fill-08`, a full pill.
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: c.fill08,
      borderRadius: BorderRadius.circular(StizeRadius.radiusPill),
    ),
    child: Text(text, style: StizeType.control.copyWith(color: c.ink)),
  );
}
