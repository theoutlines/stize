import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/stize_icons.dart';
import '../../core/design/stize_tokens.dart';
import '../../domain/models/favorite_stop.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'stop_report_sheet.dart';

/// Public address of a stop, for Share stop (the `/stop/:id` deep link).
String stopShareUrl(String stopId) =>
    'https://stize.app/stop/${Uri.encodeComponent(stopId)}';

/// What sits right after a stop's name in every stop header (owner,
/// 2026-11-24): a small filled star when the stop is in My Stops (a status,
/// not a button) and the More button. More is next to the name, away from the
/// close button, so it is never hit by mistake. Favourite, share and report
/// are rare actions, so they live in the More menu, not on screen.
class StopHeaderActions extends ConsumerWidget {
  const StopHeaderActions({
    super.key,
    required this.stopId,
    required this.stopName,
  });

  final String stopId;
  final String stopName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = StizeColors.of(context);
    final l10n = AppLocalizations.of(context);
    final isFav = ref
        .watch(favoritesControllerProvider)
        .maybeWhen(
          data: (favs) => favs.any((f) => f.stopId == stopId),
          orElse: () => false,
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isFav)
          Padding(
            padding: const EdgeInsets.only(left: StizeSpace.space2),
            child: Semantics(
              label: l10n.stopInMyStops,
              child: Icon(StizeIcons.starFilled, size: 18, color: c.favorite),
            ),
          ),
        _MoreButton(stopId: stopId, stopName: stopName, isFav: isFav),
      ],
    );
  }
}

enum _StopAction { favorite, share, report }

class _MoreButton extends ConsumerWidget {
  const _MoreButton({
    required this.stopId,
    required this.stopName,
    required this.isFav,
  });

  final String stopId;
  final String stopName;
  final bool isFav;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = StizeColors.of(context);
    final l10n = AppLocalizations.of(context);
    // A 32px fill-07 circle in a 44px tap box: the same round control as the
    // header's close button, so the two read as one family.
    return Semantics(
      button: true,
      label: l10n.stopMore,
      child: InkResponse(
        radius: 22,
        onTap: () => _open(context, ref),
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.fill07,
              ),
              child: SizedBox.square(
                dimension: 32,
                child: Icon(StizeIcons.more, size: 18, color: c.ink75),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final c = StizeColors.of(context);
    final l10n = AppLocalizations.of(context);
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(
      Offset(0, box.size.height),
      ancestor: overlay,
    );
    PopupMenuItem<_StopAction> item(
      _StopAction value,
      IconData icon,
      String label,
    ) => PopupMenuItem<_StopAction>(
      value: value,
      height: 48,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: c.ink60),
          const SizedBox(width: StizeSpace.space3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: StizeType.body.copyWith(color: c.ink),
            ),
          ),
        ],
      ),
    );
    final picked = await showMenu<_StopAction>(
      context: context,
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
      color: c.raised,
      elevation: 8,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(StizeRadius.radiusButton),
        ),
      ),
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy,
        overlay.size.width - origin.dx,
        0,
      ),
      items: [
        item(
          _StopAction.favorite,
          isFav ? StizeIcons.starFilled : StizeIcons.star,
          isFav ? l10n.removeFromFavorites : l10n.addToFavorites,
        ),
        item(_StopAction.share, StizeIcons.share, l10n.stopShare),
        item(_StopAction.report, StizeIcons.flag, l10n.stopReportProblem),
      ],
    );
    if (picked == null || !context.mounted) return;
    switch (picked) {
      case _StopAction.favorite:
        final notifier = ref.read(favoritesControllerProvider.notifier);
        if (isFav) {
          notifier.remove(stopId);
        } else {
          notifier.add(FavoriteStop(stopId: stopId, name: stopName));
        }
      case _StopAction.share:
        await Clipboard.setData(ClipboardData(text: stopShareUrl(stopId)));
        if (!context.mounted) return;
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(l10n.stopLinkCopied)));
      case _StopAction.report:
        await showStopReportSheet(context, stopId: stopId, stopName: stopName);
    }
  }
}
