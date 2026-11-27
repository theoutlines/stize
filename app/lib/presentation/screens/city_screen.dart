import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/design/components/stize_line_badge.dart';
import '../../core/design/stize_icons.dart';
import '../../core/design/stize_tokens.dart';
import '../../core/map_support.dart';
import '../../domain/models/city_analytics.dart';
import '../../domain/models/line_analytics.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';

part 'city/city_heatmap.dart';
part 'city/city_treemap.dart';
part 'city/city_blocks.dart';
part 'city/city_line_screen.dart';

// City section (the transport analytics spec (internal); canvas page "Город: аналитика",
// owner-approved 2026-11-23). Every block: one chart and one sentence. Neutral
// ink ramp; two signals only: accent = best, late = problem. Transport colours
// appear only as the small mark next to a line number.

/// Delay (seconds) → heat level 0..5; 5 is the `late` signal.
int delayLevel(int secs) {
  if (secs <= 60) return 0;
  if (secs <= 120) return 1;
  if (secs <= 180) return 2;
  if (secs <= 300) return 3;
  if (secs <= 420) return 4;
  return 5;
}

const _shade = [0.06, 0.14, 0.26, 0.42, 0.62];

Color _levelColor(StizeColors c, int level) =>
    level >= 5 ? c.late : c.ink.withValues(alpha: _shade[level]);

/// "on time" / "3 min late" / "2 min early" for a signed mean delay.
String delayText(AppLocalizations l10n, int secs) {
  final m = (secs.abs() / 60).round();
  if (m == 0) return l10n.cityOnTime;
  return secs > 0 ? l10n.cityLateBy(m) : l10n.cityEarlyBy(m);
}

String _dayName(BuildContext context, int dow) {
  // 2023-01-01 was a Sunday (dow 0).
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.E(locale).format(DateTime(2023, 1, 1 + dow));
}

/// Makes sure line numbers resolve to their transport type here too (the home
/// map installs the index lazily; a deep link to the City page comes first).
final _lineTypesReady = FutureProvider<bool>((ref) async {
  final lines = await ref.read(linesRepositoryProvider).getAll();
  if (lines.isNotEmpty) setLineTypeIndex(LineTypeIndex.fromLines(lines));
  return lines.isNotEmpty;
});

/// Days in Belgrade reading order: Monday first.
const _weekOrder = [1, 2, 3, 4, 5, 6, 0];

class CityScreen extends ConsumerWidget {
  const CityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.watch(_lineTypesReady);
    final async = ref.watch(citySummaryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cityTitle)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _Message(
          icon: StizeIcons.offline,
          title: l10n.noNetworkTitle,
          body: l10n.noNetworkSubtitle,
          action: TextButton(
            onPressed: () => ref.invalidate(citySummaryProvider),
            child: Text(l10n.retry),
          ),
        ),
        data: (s) => s.arrivals < kCityLineMinSamples
            ? _Message(
                icon: StizeIcons.stats,
                title: l10n.cityEmptyTitle,
                body: l10n.cityEmptyBody(kCityLineMinSamples),
              )
            : _CityBody(summary: s),
      ),
    );
  }
}

class _CityBody extends StatelessWidget {
  const _CityBody({required this.summary});
  final CitySummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 840;
        final kpis = LayoutBuilder(
          builder: (context, b) => _Kpis(
            summary: summary,
            // Four in a row only when each cell has room for its number.
            columns: b.maxWidth >= 640 ? 4 : 2,
          ),
        );
        final heat = _Section(
          title: l10n.cityHeatTitle,
          subtitle: l10n.cityHeatSubtitle,
          sentence: _heatSentence(context, l10n),
          child: DelayHeatmap(cells: summary.grid),
        );
        final lines = _Section(
          title: l10n.cityLinesTitle,
          subtitle: l10n.cityLinesSubtitle,
          sentence: _linesSentence(l10n),
          child: LinesTreemap(lines: summary.lines, tall: wide),
        );
        final intervals = _Section(
          title: l10n.cityIntervalsTitle,
          subtitle: l10n.cityIntervalsSubtitle,
          child: _Intervals(lines: summary.lines),
        );
        final note = _Note(text: l10n.cityNote);
        final header = _Header(
          title: l10n.cityHeadline,
          subtitle: l10n.citySubtitle,
        );
        if (!wide) {
          return ListView(
            padding: const EdgeInsets.only(bottom: StizeSpace.space8),
            children: [
              header,
              kpis,
              const _Hair(),
              heat,
              const _Hair(),
              lines,
              const _Hair(),
              intervals,
              note,
            ],
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(StizeSpace.space6),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 11,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        header,
                        kpis,
                        const _Hair(),
                        heat,
                        const _Hair(),
                        intervals,
                        note,
                      ],
                    ),
                  ),
                  const SizedBox(width: StizeSpace.space8),
                  Expanded(flex: 9, child: lines),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String? _heatSentence(BuildContext context, AppLocalizations l10n) {
    CityCell? worst;
    for (final c in summary.grid) {
      if (c.delayCount < kCityCellMinSamples || c.meanDelaySecs == null) {
        continue;
      }
      if (worst == null || c.meanDelaySecs! > worst.meanDelaySecs!) worst = c;
    }
    if (worst == null || worst.meanDelaySecs! < 60) return null;
    return l10n.cityHeatWorst(
      _dayName(context, worst.dow),
      worst.hour,
      (worst.meanDelaySecs! / 60).round(),
    );
  }

  String? _linesSentence(AppLocalizations l10n) {
    final r = judgeLines(summary.lines.take(17).toList());
    if (r.best == null) return null;
    if (r.worst == null) return l10n.cityLinesBestOnly(r.best!);
    return l10n.cityLinesSummary(r.best!, r.worst!);
  }
}

/// Best = smallest absolute mean delay, worst = largest mean delay, among lines
/// with enough timetable-matched arrivals.
({String? best, String? worst}) judgeLines(List<CityLine> lines) {
  final judged = lines
      .where(
        (l) => l.delayCount >= kCityLineMinSamples && l.meanDelaySecs != null,
      )
      .toList();
  if (judged.length < 2) return (best: null, worst: null);
  final best = judged.reduce(
    (a, b) => a.meanDelaySecs!.abs() <= b.meanDelaySecs!.abs() ? a : b,
  );
  final worst = judged.reduce(
    (a, b) => a.meanDelaySecs! >= b.meanDelaySecs! ? a : b,
  );
  // A "latest" line that is still on time is not a finding: no worst then.
  return (
    best: best.line,
    worst: worst.meanDelaySecs! >= 60 && worst != best ? worst.line : null,
  );
}
