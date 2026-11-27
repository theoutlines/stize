part of '../city_screen.dart';

// The lines treemap: one tile per line, sized by riders, coloured by delay.

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
