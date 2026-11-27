part of '../city_screen.dart';

// The delay heatmap: hours across, days down, coloured by typical delay.

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
