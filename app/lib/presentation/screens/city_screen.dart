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

// City section (docs/TRANSPORT_ANALYTICS.md; canvas page "Город: аналитика",
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
          icon: StizeIcons.nearMeOff,
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

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        StizeSpace.space4,
        StizeSpace.space2,
        StizeSpace.space4,
        StizeSpace.space2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: StizeType.section.copyWith(color: c.ink)),
          const SizedBox(height: StizeSpace.space1),
          Text(subtitle, style: StizeType.caption.copyWith(color: c.ink60)),
        ],
      ),
    );
  }
}

class _Hair extends StatelessWidget {
  const _Hair();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: StizeSpace.space4,
      vertical: StizeSpace.space2,
    ),
    child: Divider(height: 1, color: StizeColors.of(context).line),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.child,
    this.sentence,
  });
  final String title;
  final String subtitle;
  final Widget child;
  final String? sentence;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: StizeSpace.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(title: title, subtitle: subtitle),
          const SizedBox(height: StizeSpace.space2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: StizeSpace.space4),
            child: child,
          ),
          if (sentence != null) ...[
            const SizedBox(height: StizeSpace.space3),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: StizeSpace.space4,
              ),
              child: Text(
                sentence!,
                style: StizeType.body.copyWith(color: c.ink85),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.summary, required this.columns});
  final CitySummary summary;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = StizeColors.of(context);
    final nf = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final judgedLines = summary.lines
        .where((l) => l.arrivals >= kCityLineMinSamples)
        .length;
    final cells = [
      _Kpi(
        icon: StizeIcons.clock,
        label: l10n.cityKpiDelay,
        value: summary.delayCount >= kCityLineMinSamples
            ? delayText(l10n, summary.meanDelaySecs ?? 0)
            : '–',
      ),
      _Kpi(
        icon: StizeIcons.repeat,
        label: l10n.cityKpiInterval,
        value:
            summary.headwayCount >= kCityLineMinSamples &&
                summary.meanHeadwaySecs != null
            ? l10n.cityMin((summary.meanHeadwaySecs! / 60).round())
            : '–',
      ),
      _Kpi(
        icon: StizeIcons.bus,
        label: l10n.cityKpiLines,
        value: nf.format(judgedLines),
      ),
      _Kpi(
        icon: StizeIcons.stats,
        label: l10n.cityKpiArrivals,
        value: nf.format(summary.arrivals),
      ),
    ];
    final side = BorderSide(color: c.line);
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += columns) {
      final last = i + columns >= cells.length;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = i; j < math.min(i + columns, cells.length); j++)
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        right: j % columns == columns - 1
                            ? BorderSide.none
                            : side,
                        bottom: last ? BorderSide.none : side,
                      ),
                    ),
                    child: cells[j],
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(StizeSpace.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: c.ink80),
              const SizedBox(width: StizeSpace.space2),
              Flexible(
                child: Text(
                  label,
                  style: StizeType.caption.copyWith(color: c.ink80),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: StizeSpace.space2),
          Text(
            value,
            style: StizeType.h1.copyWith(color: c.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Weekday × hour grid of the mean delay. Cells with too few timetable-matched
/// arrivals stay empty (outlined). Tapping a cell shows its number and sample.
class DelayHeatmap extends StatefulWidget {
  const DelayHeatmap({super.key, required this.cells});
  final List<CityCell> cells;

  @override
  State<DelayHeatmap> createState() => _DelayHeatmapState();
}

class _DelayHeatmapState extends State<DelayHeatmap> {
  CityCell? _picked;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    final l10n = AppLocalizations.of(context);
    final byKey = {for (final x in widget.cells) '${x.dow}:${x.hour}': x};
    const labelW = 28.0;
    const gap = 2.0;
    return LayoutBuilder(
      builder: (context, box) {
        final size = ((box.maxWidth - labelW - gap * 23) / 24).clamp(8.0, 28.0);
        final axis = StizeType.mono.copyWith(color: c.ink50, fontSize: 10);
        Widget cell(int dow, int hour) {
          final x = byKey['$dow:$hour'];
          final enough =
              x != null &&
              x.delayCount >= kCityCellMinSamples &&
              x.meanDelaySecs != null;
          final picked =
              _picked != null && _picked!.dow == dow && _picked!.hour == hour;
          return GestureDetector(
            onTap: () => setState(
              () => _picked = picked
                  ? null
                  : (x ??
                        CityCell(
                          dow: dow,
                          hour: hour,
                          arrivals: 0,
                          delayCount: 0,
                          meanDelaySecs: null,
                          headwayCount: 0,
                          meanHeadwaySecs: null,
                        )),
            ),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: enough
                    ? _levelColor(c, delayLevel(x.meanDelaySecs!))
                    : null,
                border: enough
                    ? (picked ? Border.all(color: c.ink, width: 2) : null)
                    : Border.all(color: picked ? c.ink : c.fill10),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          );
        }

        final picked = _picked;
        String? tip;
        if (picked != null) {
          final head = l10n.cityHeatCell(
            _dayName(context, picked.dow),
            picked.hour,
            (picked.hour + 1) % 24,
          );
          final enough =
              picked.delayCount >= kCityCellMinSamples &&
              picked.meanDelaySecs != null;
          final body = enough
              ? delayText(l10n, picked.meanDelaySecs!)
              : l10n.cityHeatFew;
          tip = '$head · $body · ${l10n.cityHeatCellCount(picked.arrivals)}';
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: labelW),
                for (var h = 0; h < 24; h++) ...[
                  SizedBox(
                    width: size,
                    child: Text(
                      h % 6 == 0 ? '$h' : '',
                      style: axis,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.visible,
                      softWrap: false,
                    ),
                  ),
                  if (h < 23) const SizedBox(width: gap),
                ],
              ],
            ),
            const SizedBox(height: gap),
            for (final d in _weekOrder) ...[
              Row(
                children: [
                  SizedBox(
                    width: labelW,
                    child: Text(
                      _dayName(context, d).toLowerCase(),
                      style: axis,
                      maxLines: 1,
                    ),
                  ),
                  for (var h = 0; h < 24; h++) ...[
                    cell(d, h),
                    if (h < 23) const SizedBox(width: gap),
                  ],
                ],
              ),
              const SizedBox(height: gap),
            ],
            const SizedBox(height: StizeSpace.space2),
            Padding(
              padding: const EdgeInsets.only(left: labelW),
              child: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    l10n.cityLegendLow,
                    style: StizeType.caption.copyWith(color: c.ink60),
                  ),
                  for (var i = 0; i < 6; i++)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _levelColor(c, i),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  Text(
                    l10n.cityLegendHigh,
                    style: StizeType.caption.copyWith(color: c.ink60),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: StizeMotion.fast,
              curve: StizeMotion.smoothOut,
              child: tip == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: StizeSpace.space3),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(StizeSpace.space3),
                        decoration: BoxDecoration(
                          color: c.fill06,
                          borderRadius: BorderRadius.circular(
                            StizeRadius.radiusMd,
                          ),
                        ),
                        child: Text(
                          tip,
                          style: StizeType.caption.copyWith(color: c.ink),
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Lines as tiles: size = arrivals seen, number = mean delay. Accent = most
/// punctual, late = latest, outlined = too few arrivals to judge.
class LinesTreemap extends StatelessWidget {
  const LinesTreemap({super.key, required this.lines, this.tall = false});
  final List<CityLine> lines;
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    final l10n = AppLocalizations.of(context);
    final top = lines.take(17).toList();
    // Best/worst among the tiles on screen, so the sentence names what you see.
    final judged = judgeLines(top);
    const counts = [3, 4, 5, 5];
    final heights = tall
        ? [200.0, 150.0, 116.0, 84.0]
        : [140.0, 104.0, 80.0, 60.0];
    final rows = <Widget>[];
    var i = 0;
    for (var r = 0; r < counts.length && i < top.length; r++) {
      final chunk = top.skip(i).take(counts[r]).toList();
      i += chunk.length;
      rows.add(
        SizedBox(
          height: heights[r],
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var k = 0; k < chunk.length; k++) ...[
                Expanded(
                  // Square root: one very busy line must not squeeze the
                  // rest of its row into unreadable slivers.
                  flex: math.max(1, math.sqrt(chunk[k].arrivals).round()),
                  child: _Tile(
                    line: chunk[k],
                    best: chunk[k].line == judged.best,
                    worst: chunk[k].line == judged.worst,
                    small: heights[r] < 70,
                  ),
                ),
                if (k < chunk.length - 1) const SizedBox(width: 4),
              ],
            ],
          ),
        ),
      );
      rows.add(const SizedBox(height: 4));
    }
    Widget key(Color? fill, String label, {bool outline = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: fill,
            border: outline ? Border.all(color: c.fill24) : null,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: StizeType.caption.copyWith(color: c.ink60)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...rows,
        const SizedBox(height: StizeSpace.space2),
        Wrap(
          spacing: StizeSpace.space4,
          runSpacing: StizeSpace.space1,
          children: [
            key(c.accent, l10n.cityLegendBest),
            key(c.late, l10n.cityLegendWorst),
            key(null, l10n.cityLegendThin, outline: true),
          ],
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.line,
    required this.best,
    required this.worst,
    required this.small,
  });
  final CityLine line;
  final bool best;
  final bool worst;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    final l10n = AppLocalizations.of(context);
    final judged =
        line.delayCount >= kCityLineMinSamples && line.meanDelaySecs != null;
    final Color? bg;
    final Color fg;
    if (best) {
      bg = c.accent;
      fg = c.onAccent;
    } else if (worst) {
      bg = c.late;
      fg = Colors.white;
    } else if (judged) {
      bg = c.ink.withValues(
        alpha: 0.08 + 0.1 * delayLevel(line.meanDelaySecs!).clamp(0, 4),
      );
      fg = c.ink;
    } else {
      bg = null;
      fg = c.ink60;
    }
    final value = judged
        ? (line.meanDelaySecs!.abs() < 60
              ? l10n.cityOnTime
              : '${line.meanDelaySecs! > 0 ? '+' : '−'}${l10n.cityMin((line.meanDelaySecs!.abs() / 60).round())}')
        : '–';
    return Material(
      color: bg ?? Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StizeRadius.radiusXs),
        side: bg == null ? BorderSide(color: c.fill24) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            context.push('/analytics/${Uri.encodeComponent(line.line)}'),
        child: Padding(
          padding: const EdgeInsets.all(StizeSpace.space2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: vehicleColor(lineTypeOf(line.line)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      line.line,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: StizeType.lineNumber.copyWith(
                        color: fg,
                        fontSize: small ? 13 : 16,
                      ),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.bottomRight,
                // Narrow tiles shrink the number instead of cutting it.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: StizeType.mono.copyWith(
                      color: fg,
                      fontSize: small ? 11 : 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Intervals extends StatelessWidget {
  const _Intervals({required this.lines});
  final List<CityLine> lines;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    final l10n = AppLocalizations.of(context);
    final items =
        lines
            .where(
              (l) =>
                  l.eveningHeadwayCount >= kCityCellMinSamples &&
                  l.eveningMeanHeadwaySecs != null,
            )
            .toList()
          ..sort(
            (a, b) =>
                b.eveningMeanHeadwaySecs!.compareTo(a.eveningMeanHeadwaySecs!),
          );
    final top = items.take(5).toList();
    if (top.isEmpty) {
      return Text(
        l10n.cityHeatFew,
        style: StizeType.caption.copyWith(color: c.ink60),
      );
    }
    final mx = top.first.eveningMeanHeadwaySecs!;
    return LayoutBuilder(
      builder: (context, box) => Column(
        children: [
          for (final l in top)
            Padding(
              padding: const EdgeInsets.only(bottom: StizeSpace.space2),
              child: InkWell(
                onTap: () =>
                    context.push('/analytics/${Uri.encodeComponent(l.line)}'),
                borderRadius: BorderRadius.circular(StizeRadius.radiusXs),
                child: Row(
                  children: [
                    Container(
                      width:
                          64 +
                          (box.maxWidth - 160) * l.eveningMeanHeadwaySecs! / mx,
                      height: 36,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        color: c.fill08,
                        borderRadius: BorderRadius.circular(
                          StizeRadius.radiusXs,
                        ),
                      ),
                      child: StizeLineBadge(line: l.line),
                    ),
                    const Spacer(),
                    Text(
                      l10n.cityMin((l.eveningMeanHeadwaySecs! / 60).round()),
                      style: StizeType.mono.copyWith(color: c.ink),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(StizeSpace.space4),
      child: Container(
        padding: const EdgeInsets.all(StizeSpace.space3),
        decoration: BoxDecoration(
          color: c.fill06,
          borderRadius: BorderRadius.circular(StizeRadius.radiusMd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(StizeIcons.info, size: 18, color: c.ink60),
            const SizedBox(width: StizeSpace.space2),
            Expanded(
              child: Text(
                text,
                style: StizeType.caption.copyWith(color: c.ink60),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(StizeSpace.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: c.ink60),
            const SizedBox(height: StizeSpace.space3),
            Text(
              title,
              style: StizeType.section.copyWith(color: c.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: StizeSpace.space2),
            Text(
              body,
              style: StizeType.body.copyWith(color: c.ink60),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: StizeSpace.space4),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Line page.

/// Line analytics cells are UTC; the page speaks Belgrade time (+1h, same
/// fixed shift as the backend's city summary).
CityCell _localCell(AnalyticsCell a) {
  final h = a.hour + 1;
  return CityCell(
    dow: (a.dow + h ~/ 24) % 7,
    hour: h % 24,
    arrivals: a.arrivals,
    delayCount: a.delayCount,
    meanDelaySecs: a.meanDelaySecs?.round(),
    headwayCount: a.meanHeadwaySecs == null ? 0 : kCityCellMinSamples,
    meanHeadwaySecs: a.meanHeadwaySecs?.round(),
  );
}

class CityLineScreen extends ConsumerWidget {
  const CityLineScreen({super.key, required this.line});
  final String line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = StizeColors.of(context);
    ref.watch(_lineTypesReady);
    final async = ref.watch(lineAnalyticsProvider(line));
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [StizeLineBadge(line: line, big: true)],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _Message(
          icon: StizeIcons.nearMeOff,
          title: l10n.noNetworkTitle,
          body: l10n.noNetworkSubtitle,
          action: TextButton(
            onPressed: () => ref.invalidate(lineAnalyticsProvider(line)),
            child: Text(l10n.retry),
          ),
        ),
        data: (a) {
          final arrivals = a.grid.fold<int>(0, (s, x) => s + x.arrivals);
          if (arrivals < kCityLineMinSamples) {
            return _Message(
              icon: StizeIcons.stats,
              title: l10n.cityEmptyTitle,
              body: l10n.cityLineThinBody(arrivals, kCityLineMinSamples),
            );
          }
          final cells = a.grid.map(_localCell).toList();
          final now = DateTime.now();
          final nowDow = now.weekday % 7;
          final here = cells
              .where((x) => x.dow == nowDow && x.hour == now.hour)
              .firstOrNull;
          // Fall back to the same hour on any day when this cell is empty.
          int? usual = here?.meanHeadwaySecs;
          if (usual == null) {
            final same = cells
                .where((x) => x.hour == now.hour && x.meanHeadwaySecs != null)
                .toList();
            if (same.isNotEmpty) {
              usual =
                  same.map((x) => x.meanHeadwaySecs!).reduce((p, q) => p + q) ~/
                  same.length;
            }
          }
          var dc = 0;
          var ds = 0.0;
          for (final x in a.grid) {
            if (x.meanDelaySecs == null) continue;
            dc += x.delayCount;
            ds += x.meanDelaySecs! * x.delayCount;
          }
          Widget stat(String label, String value) => Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: StizeType.caption.copyWith(color: c.ink60)),
                const SizedBox(height: StizeSpace.space1),
                Text(value, style: StizeType.h1.copyWith(color: c.ink)),
              ],
            ),
          );
          return ListView(
            padding: const EdgeInsets.only(bottom: StizeSpace.space8),
            children: [
              Padding(
                padding: const EdgeInsets.all(StizeSpace.space4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    stat(
                      l10n.cityLineUsual,
                      usual == null
                          ? l10n.cityLineNoHour
                          : l10n.cityLineEvery((usual / 60).round()),
                    ),
                    const SizedBox(width: StizeSpace.space4),
                    stat(
                      l10n.cityKpiDelay,
                      dc >= kCityLineMinSamples
                          ? delayText(l10n, (ds / dc).round())
                          : '–',
                    ),
                  ],
                ),
              ),
              const _Hair(),
              _Section(
                title: l10n.cityHeatTitle,
                subtitle: l10n.cityLineHeatSubtitle,
                child: DelayHeatmap(cells: cells),
              ),
              _Note(text: l10n.cityNote),
            ],
          );
        },
      ),
    );
  }
}
