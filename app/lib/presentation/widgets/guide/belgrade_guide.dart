import 'dart:math' as math;
import 'package:stize/core/design/stize_text.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../stretch_card_list.dart';
import '../../../core/design/stize_icons.dart';
import '../../../core/design/stize_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../flat_cards.dart';

/// Pages of the Belgrade guide, each shown as a level in the map's sheet /
/// desktop panel (owner-approved 2026-11-23, design v5).
enum GuidePage { home, readStop, places }

/// Transport hubs: the guide links to them, and the Nearby strip appears when
/// the user is within [GuideHub.radiusM] of one. Stop ids are GTFS stops.
enum GuideHub {
  // Arrivals (dolasci). The airport is a loop: buses from town stop at
  // departures (polasci, 21045), end the trip at arrivals and leave for town
  // from there, so arrivals is the stop a traveller who just landed needs.
  airport('22303', 44.8204, 20.29031),
  busStation('21062', 44.80395, 20.41700),
  railStation('21041', 44.79274, 20.45429);

  const GuideHub(this.stopId, this.lat, this.lon);
  final String stopId;
  final double lat;
  final double lon;

  static const double radiusM = 300;
}

/// A place people ask for, opened as its nearest stop (GTFS ids).
class GuidePlace {
  const GuidePlace(this.name, this.area, this.stopId);
  final String name;
  final String area;
  final String stopId;
}

const kGuidePlaces = <GuidePlace>[
  GuidePlace('Belgrade Fortress', 'Kalemegdan · Studentski trg', '20650'),
  GuidePlace('Trg Republike', 'Knez Mihailova, old town', '20193'),
  GuidePlace('Slavija', 'Vračar, Saint Sava temple', '20200'),
  GuidePlace('Ada Ciganlija', 'Lake and beaches', '20503'),
  GuidePlace('Nikola Tesla Airport', 'Arrivals, buses into the city', '22303'),
  GuidePlace('Beogradska autobuska stanica', 'Main bus station', '21062'),
  GuidePlace('Beograd Centar', 'Railway station (Prokop)', '21041'),
];

/// Expo 2027 opening day (Belgrade, 15 May 2027).
final DateTime kExpoOpening = DateTime(2027, 5, 15);

/// Night hours for the guide's night state (00:00 to 04:59 local).
bool isNightHour(DateTime now) => now.hour < 5;

/// The guide's root page.
class GuideHome extends StatelessWidget {
  const GuideHome({
    super.key,
    required this.onOpenPage,
    required this.onOpenStop,
    this.scrollController,
    this.now,
  });

  final void Function(GuidePage page) onOpenPage;
  final void Function(String stopId, String name) onOpenStop;
  final ScrollController? scrollController;

  /// Clock override for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = now ?? DateTime.now();
    return StretchCardList(
      controller: scrollController,
      shrinkWrap: scrollController == null,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _FreeLine(text: l10n.guideFree),
        const SizedBox(height: 12),
        isNightHour(t) ? _NightCard(l10n: l10n) : _ExpoCard(l10n: l10n, now: t),
        _Section(l10n.guideGettingAround),
        GuideRow(
          icon: StizeIcons.luggage,
          title: l10n.guideFromAirport,
          subtitle: l10n.guideFromAirportSub,
          onTap: () =>
              onOpenStop(GuideHub.airport.stopId, 'Aerodrom Nikola Tesla'),
        ),
        GuideRow(
          icon: StizeIcons.bus,
          title: l10n.guideFromBusStation,
          subtitle: l10n.guideFromBusStationSub,
          onTap: () => onOpenStop(
            GuideHub.busStation.stopId,
            'Beogradska autobuska stanica',
          ),
        ),
        GuideRow(
          icon: StizeIcons.train,
          title: l10n.guideFromRailStation,
          subtitle: l10n.guideFromRailStationSub,
          onTap: () => onOpenStop(
            GuideHub.railStation.stopId,
            'Železnička stanica BGD centar',
          ),
        ),
        GuideRow(
          icon: StizeIcons.info,
          title: l10n.guideReadStop,
          subtitle: l10n.guideReadStopSub,
          onTap: () => onOpenPage(GuidePage.readStop),
        ),
        GuideRow(
          icon: StizeIcons.pin,
          title: l10n.guidePlaces,
          subtitle: l10n.guidePlacesSub,
          onTap: () => onOpenPage(GuidePage.places),
        ),
      ],
    );
  }
}

/// "How to read a stop": four plain facts about the board.
class GuideReadStop extends StatelessWidget {
  const GuideReadStop({super.key, this.scrollController});
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = [
      (StizeIcons.nearMe, l10n.guideReadStopLive),
      (StizeIcons.clock, l10n.guideReadStopScheduled),
      (StizeIcons.star, l10n.guideReadStopStar),
      (StizeIcons.moon, l10n.guideReadStopNight),
    ];
    final theme = Theme.of(context);
    return StretchCardList(
      controller: scrollController,
      shrinkWrap: scrollController == null,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final (icon, text) in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: StizeText.of(context).body)),
              ],
            ),
          ),
      ],
    );
  }
}

/// "Places people ask for": tap opens the place's stop as the next level.
class GuidePlaces extends StatelessWidget {
  const GuidePlaces({
    super.key,
    required this.onOpenStop,
    this.scrollController,
  });
  final void Function(String stopId, String name) onOpenStop;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return StretchCardList(
      controller: scrollController,
      shrinkWrap: scrollController == null,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final p in kGuidePlaces)
          GuideRow(
            icon: StizeIcons.pin,
            title: p.name,
            subtitle: p.area,
            onTap: () => onOpenStop(p.stopId, p.name),
          ),
      ],
    );
  }
}

/// A tappable row of the guide (also used for the Nearby strip).
class GuideRow extends StatelessWidget {
  const GuideRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 32,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 20, color: scheme.onSurface),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: StizeText.of(
                          context,
                        ).label.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: StizeText.of(
                          context,
                        ).caption.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(
                  StizeIcons.chevronRight,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FreeLine extends StatelessWidget {
  const _FreeLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: StizeText.of(
        context,
      ).body.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
      child: Text(
        text,
        style: StizeText.of(
          context,
        ).label.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Daytime "Right now": the Expo countdown, green (never a line colour).
class _ExpoCard extends StatelessWidget {
  const _ExpoCard({required this.l10n, required this.now});
  final AppLocalizations l10n;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Whole calendar days, in UTC so a DST change in between can't eat one.
    final today = DateTime.utc(now.year, now.month, now.day);
    final open = DateTime.utc(
      kExpoOpening.year,
      kExpoOpening.month,
      kExpoOpening.day,
    );
    final days = open.difference(today).inDays;
    if (days < 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: StizeColors.of(context).accent14,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l10n.guideNowLabel} · ${l10n.guideExpoTitle}',
            style: StizeText.of(
              context,
            ).label.copyWith(color: StizeColors.of(context).accent),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$days',
                style: StizeText.of(context).heroTitle.copyWith(
                  color: StizeColors.of(context).accent,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 8),
              Text(l10n.guideExpoDays, style: StizeText.of(context).label),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.guideExpoSub,
            style: StizeText.of(
              context,
            ).caption.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Night "Right now": navy, not a line colour.
class _NightCard extends StatelessWidget {
  const _NightCard({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    const fg = Colors.white;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: StizeColors.of(context).guideNight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(StizeIcons.moon, size: 16, color: fg),
              const SizedBox(width: 8),
              Text(
                l10n.guideNowLabel,
                style: StizeText.of(
                  context,
                ).label.copyWith(color: fg.withValues(alpha: 0.8)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.guideNightTitle,
            style: StizeText.of(
              context,
            ).section.copyWith(color: fg, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.guideNightSub,
            style: StizeText.of(
              context,
            ).caption.copyWith(color: fg.withValues(alpha: 0.75)),
          ),
        ],
      ),
    );
  }
}

const _guideOpenedKey = 'guide_opened';

/// Remembers that the guide was opened, so the first-launch strip stops.
Future<void> markGuideOpened() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_guideOpenedKey, true);
}

Future<bool> guideOpenedBefore() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_guideOpenedKey) ?? false;
}

/// The hub the user is standing at (within [GuideHub.radiusM]), if any.
GuideHub? hubNear(double lat, double lon) {
  for (final h in GuideHub.values) {
    final dy = (h.lat - lat) * 111320;
    final dx = (h.lon - lon) * 111320 * math.cos(lat * math.pi / 180);
    if (math.sqrt(dx * dx + dy * dy) <= GuideHub.radiusM) return h;
  }
  return null;
}

/// One line between the search and Nearby cards (flows B, C, D of the design):
/// night, first launch on a non-Serbian locale, or standing at a hub.
class GuideStrip extends StatelessWidget {
  const GuideStrip({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onDismiss,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Shows a × that hides the strip for good (the first-launch nudge); the
  /// contextual strips (a hub, night) carry a chevron and leave on their own.
  final VoidCallback? onDismiss;

  /// The flat strip's surface, for the list's edge stretch.
  static Color surface(StizeColors c) => c.fill08;

  @override
  Widget build(BuildContext context) {
    // One strip for mobile and desktop (owner, 2026-11-25, variant A): a row
    // in the cards' own language with the timetable cards' neutral fill.
    // Mobile: flat, flush with the sheet's top, a hairline under it. Desktop
    // island: rounded like the island's cards.
    final flat = FlatCards.of(context);
    final c = StizeColors.of(context);
    final text = StizeText.of(context);
    return Material(
      color: surface(c),
      shape: flat
          ? Border(bottom: BorderSide(color: c.stripeLine))
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(StizeRadius.radiusCard),
            ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            StizeSpace.space4,
            StizeSpace.space3,
            StizeSpace.space2,
            StizeSpace.space3,
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: StizeSpace.space3),
                child: Icon(
                  icon,
                  size: 20,
                  color: c.ink75,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.label.copyWith(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: text.caption.copyWith(color: c.ink60),
                    ),
                  ],
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  onPressed: onDismiss,
                  tooltip: AppLocalizations.of(context).close,
                  icon: Icon(
                    StizeIcons.close,
                    size: 16,
                    color: c.ink50,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(StizeSpace.space2),
                  child: Icon(
                    StizeIcons.chevronRight,
                    size: 20,
                    color: c.ink50,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
