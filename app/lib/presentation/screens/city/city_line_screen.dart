part of '../city_screen.dart';

// The page of one line (/analytics/:line).

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
          icon: StizeIcons.offline,
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
