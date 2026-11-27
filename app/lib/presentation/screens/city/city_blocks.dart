part of '../city_screen.dart';

// The small building blocks of the City pages: header, hairline, section,
// KPI row, intervals, note and message.

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
