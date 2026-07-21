import 'package:flutter/material.dart';

import '../../core/fleet_matcher.dart';
import '../../core/map_support.dart';
import '../../domain/models/vehicle_type.dart';
import '../../l10n/app_localizations.dart';
import 'fleet_badges.dart';
import 'vehicle_icon.dart';

/// The model card (task B3), opened by tapping a Fleet-ID badge in the arrivals
/// list. Shows what the passenger is about to ride: the local nickname, a plain
/// human note, and the comparison attributes in passenger-value order (spec §3).
///
/// Assumed / per-vehicle values are marked with a trailing "~" so a guess is
/// never dressed up as fact. The visual hero (interior schematic, spec §8) is a
/// separate track — a slot is reserved here, but the card ships without it.
Future<void> showFleetModelCard(
  BuildContext context, {
  required FleetVehicle fleet,
  required VehicleType fallbackType,
  String? garageNo,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => FleetModelView(
      fleet: fleet,
      fallbackType: fallbackType,
      garageNo: garageNo,
    ),
  );
}

/// The model-card content. Hosted by the mobile modal ([showFleetModelCard]) and
/// by the desktop context panel (as a leaf sub-view of the vehicle view — the
/// desktop model details live INSIDE the panel, never a second surface over it).
///
/// [scrollController] switches on the **embedded** layout: the same content, but
/// scrolling with the host's controller and WITHOUT its own SafeArea /
/// max-height clamp — used when the card is a subview inside a mobile bottom
/// sheet (owner B#2, so the sheet's chrome/detents own the frame). Null keeps the
/// standalone layout (the legacy modal + the desktop panel leaf).
class FleetModelView extends StatelessWidget {
  const FleetModelView({
    super.key,
    required this.fleet,
    required this.fallbackType,
    this.garageNo,
    this.scrollController,
  });

  final FleetVehicle fleet;
  final VehicleType fallbackType;
  final String? garageNo;

  /// When non-null, embed inside a scrollable host (the mobile sheet) using this
  /// controller instead of wrapping in a self-sized modal frame.
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final note = fleet.humanNoteFor(lang);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, theme, l10n, lang),
        const SizedBox(height: 12),
        _heroSlot(context, theme),
        if (note != null) ...[
          const SizedBox(height: 14),
          Text(note, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 16),
        ..._attributes(context, theme, l10n, lang),
        if (fleet.approximate) ...[
          const SizedBox(height: 14),
          Text(
            l10n.fleetApproxNote,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ],
    );

    // Embedded in a mobile sheet: fill the sheet, scroll with its controller.
    // The sheet already provides the drag handle, radius, background and back
    // header — so no SafeArea / ConstrainedBox / own handle here.
    if (scrollController != null) {
      return SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: content,
      );
    }

    // Standalone (legacy modal / desktop panel leaf) — unchanged.
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: content,
        ),
      ),
    );
  }

  Widget _header(
      BuildContext context, ThemeData theme, AppLocalizations l10n, String lang) {
    final model = fleet.modelName ?? l10n.fleetUnknownModel;
    // Model name is the headline; the local nickname sits small beneath it, and
    // only for locales that understand it (ru/sr) — see [nicknameFor].
    final nickname = fleet.nicknameFor(lang);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: vehicleColor(fallbackType),
          child: vehicleGlyph(fallbackType, size: 24, color: Colors.white),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                model,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (nickname != null)
                Text(
                  nickname,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Reserved slot for the §8 interior schematic. Until that track ships, it's
  /// a quiet placeholder so the card's layout already accounts for the hero.
  Widget _heroSlot(BuildContext context, ThemeData theme) {
    return Container(
      height: 96,
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(
        vehicleIconFor(fallbackType),
        size: 40,
        color: theme.colorScheme.outlineVariant,
      ),
    );
  }

  List<Widget> _attributes(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    String lang,
  ) {
    final rows = <Widget>[];

    // 1) Air conditioning — the headline question of a Belgrade summer.
    if (fleet.ac != null) {
      rows.add(_row(
        theme,
        fleet.ac! ? Icons.ac_unit : Icons.wb_sunny_outlined,
        fleet.ac! ? l10n.fleetAc : l10n.fleetNoAc,
        positive: fleet.ac!,
        assumed: fleet.isAssumed('ac'),
      ));
    }

    // 2) Low floor.
    if (fleet.lowFloor != null) {
      rows.add(_row(
        theme,
        fleet.lowFloor! ? Icons.accessible : Icons.stairs_outlined,
        fleet.lowFloor! ? l10n.fleetLowFloor : l10n.fleetHighFloor,
        positive: fleet.lowFloor!,
        assumed: fleet.isAssumed('low_floor'),
      ));
    }

    // 3) Age.
    final age = fleetAgeYears(fleet);
    final years = fleet.yearsBuilt;
    if (age != null && years != null) {
      final assumed = fleet.isAssumed('years_built');
      rows.add(_row(
        theme,
        Icons.history,
        assumed
            ? l10n.fleetAgeApprox(age, years[0], years[1])
            : '${l10n.fleetAge}: ${l10n.fleetAgeYears(age)}',
        assumed: assumed,
      ));
    }

    // 4) Comfort — not a number, a five-dot scale + a word (spec §4).
    if (fleet.comfortScore != null) {
      rows.add(_comfortRow(theme, l10n, fleet.comfortScore!, fleet.approximate));
    }

    // 5) Capacity / articulated / length.
    if (fleet.articulated == true) {
      rows.add(_row(theme, Icons.airline_seat_flat_angled, l10n.fleetArticulated,
          assumed: fleet.approximate));
    }
    if (fleet.capacity != null) {
      rows.add(_row(theme, Icons.groups_outlined, l10n.fleetCapacity(fleet.capacity!),
          assumed: fleet.approximate));
    }
    if (fleet.lengthM != null) {
      rows.add(_row(theme, Icons.straighten,
          l10n.fleetLength(_trimMeters(fleet.lengthM!)),
          assumed: fleet.approximate));
    }

    // 6) Powertrain — eco badge.
    final power = _powertrainLabel(l10n, fleet.powertrain);
    if (power != null) {
      rows.add(_row(
        theme,
        fleet.powertrain.isElectric ? Icons.eco : Icons.local_gas_station_outlined,
        power,
        positive: fleet.powertrain.isElectric,
        assumed: fleet.approximate,
      ));
    }

    // 7) USB.
    if (fleet.usb == true) {
      rows.add(_row(theme, Icons.usb, l10n.fleetUsb, assumed: fleet.isAssumed('usb')));
    }

    // Details: manufacturer + country of origin (concrete-model classes only).
    if (fleet.manufacturer != null) {
      final country = fleet.country == null
          ? null
          : _localizedCountry(fleet.country!, lang);
      final value = country == null
          ? fleet.manufacturer!
          : '${fleet.manufacturer}, $country';
      rows.add(_row(theme, Icons.factory_outlined, l10n.fleetManufacturer(value),
          muted: true));
    }

    // Details: operator (non-GSP classes only).
    if (fleet.operatorName != null) {
      rows.add(_row(theme, Icons.business_outlined,
          l10n.fleetOperator(fleet.operatorName!),
          muted: true));
    }

    return rows;
  }

  /// Localize a slash-separated country code ("DE/CH" → "Germany/Switzerland"),
  /// falling back to English, then the raw code for anything unmapped.
  static String _localizedCountry(String code, String lang) {
    return code
        .split('/')
        .map((c) {
          final names = _countryNames[c.trim()];
          if (names == null) return c.trim();
          return names[lang] ?? names['en'] ?? c.trim();
        })
        .join('/');
  }

  Widget _row(
    ThemeData theme,
    IconData icon,
    String label, {
    bool positive = false,
    bool assumed = false,
    bool muted = false,
  }) {
    final baseColor = positive
        ? const Color(0xFF1E7A46)
        : (muted ? theme.colorScheme.outline : theme.colorScheme.onSurface);
    final color = assumed ? baseColor.withValues(alpha: 0.6) : baseColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              assumed ? '$label ~' : label,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _comfortRow(
    ThemeData theme,
    AppLocalizations l10n,
    int score,
    bool assumed,
  ) {
    final word = score <= 2
        ? l10n.fleetComfortRetro
        : (score == 3 ? l10n.fleetComfortOk : l10n.fleetComfortComfy);
    final dotColor = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(Icons.chair_outlined, size: 20, color: theme.colorScheme.onSurface),
          const SizedBox(width: 12),
          Text('${l10n.fleetSectionComfort}: ',
              style: theme.textTheme.bodyMedium),
          for (var i = 1; i <= 5; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Icon(
                i <= score ? Icons.circle : Icons.circle_outlined,
                size: 10,
                color: i <= score
                    ? dotColor.withValues(alpha: assumed ? 0.6 : 1)
                    : theme.colorScheme.outlineVariant,
              ),
            ),
          const SizedBox(width: 8),
          Text(
            assumed ? '$word ~' : word,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  String? _powertrainLabel(AppLocalizations l10n, Powertrain p) {
    switch (p) {
      case Powertrain.electricBattery:
      case Powertrain.electricUltracap:
        return l10n.fleetElectric;
      case Powertrain.hybrid:
        return l10n.fleetHybrid;
      case Powertrain.cng:
        return l10n.fleetCng;
      case Powertrain.trolleybus:
        return l10n.fleetTrolley;
      case Powertrain.tram:
        return l10n.fleetTram;
      case Powertrain.diesel:
        return l10n.fleetDiesel;
      case Powertrain.unknown:
        return null;
    }
  }

  /// "18.0" → "18", "31.4" → "31.4".
  static String _trimMeters(double m) {
    final s = m.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }
}

/// Localized country-of-origin names for the codes used in the fleet data,
/// including historical ones (CS = Czechoslovakia, YU = Yugoslavia). Kept as a
/// small in-code table rather than 30+ arb keys; the UI label around it is
/// localized via l10n.
const Map<String, Map<String, String>> _countryNames = {
  'BG': {'en': 'Bulgaria', 'ru': 'Болгария', 'sr': 'Bugarska'},
  'BY': {'en': 'Belarus', 'ru': 'Беларусь', 'sr': 'Belorusija'},
  'CH': {'en': 'Switzerland', 'ru': 'Швейцария', 'sr': 'Švajcarska'},
  'CN': {'en': 'China', 'ru': 'Китай', 'sr': 'Kina'},
  'CS': {'en': 'Czechoslovakia', 'ru': 'Чехословакия', 'sr': 'Čehoslovačka'},
  'DE': {'en': 'Germany', 'ru': 'Германия', 'sr': 'Nemačka'},
  'ES': {'en': 'Spain', 'ru': 'Испания', 'sr': 'Španija'},
  'PL': {'en': 'Poland', 'ru': 'Польша', 'sr': 'Poljska'},
  'RS': {'en': 'Serbia', 'ru': 'Сербия', 'sr': 'Srbija'},
  'TR': {'en': 'Turkey', 'ru': 'Турция', 'sr': 'Turska'},
  'YU': {'en': 'Yugoslavia', 'ru': 'Югославия', 'sr': 'Jugoslavija'},
};
