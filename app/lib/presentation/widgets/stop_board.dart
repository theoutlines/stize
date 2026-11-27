import 'stretch_card_list.dart';
import 'package:stize/core/design/stize_text.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/arrival.dart';
import '../../domain/models/route_alert.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'empty_state.dart';
import 'stop_arrivals_list.dart';
import 'jam_stop_banner.dart';
import 'route_alerts_strip.dart';
import 'sheet_chrome.dart';
import 'stop_header_actions.dart';
import 'stop_live_refresh.dart';
import '../../core/design/stize_icons.dart';

/// The reusable "stop" view — a stop's live arrivals board, with no assumption
/// about its container. It is hosted BY three shells that only add chrome:
///
///  * the mobile bottom sheet ([showStopSheet] → `_StopSheet`);
///  * the desktop context panel ([ContextPanel]).
///
/// Extracting it here is exactly the "no duplication of lists/sheets" the
/// context-panel task requires (and progresses the CLAUDE.md shared-board
/// backlog item): the board grouping/dedup/fleet logic lives in ONE place.
///
/// The header (stop name + favourite star + a close affordance) is rendered
/// here so every shell gets it identically; a shell that wants its own header
/// chrome passes [showHeader] = false (the desktop panel supplies the search +
/// back-chip above and lets the board render the title row).
class StopBoard extends ConsumerStatefulWidget {
  const StopBoard({
    super.key,
    required this.stopId,
    this.initialStopName,
    this.onFocusVehicle,
    this.onClose,
    this.scrollController,
    this.showHeader = true,
  });

  final String stopId;
  final String? initialStopName;

  /// Called with the tapped arrival (and the board's as-of time, which anchors
  /// its timed-trajectory plan) when a live row is selected, so the host (the
  /// map) can build a guaranteed marker, highlight the route and follow. The
  /// host is responsible for closing/advancing the container first if needed.
  final void Function(Arrival arrival, DateTime asOf)? onFocusVehicle;

  /// Renders a close (×) button in the header when non-null (pop the sheet /
  /// return the slot to nearby). Omitted → no close button (e.g. a panel whose
  /// chrome owns the ×).
  final VoidCallback? onClose;

  /// Provided by a scrolling container (the sheet's DraggableScrollableSheet);
  /// null lets the board scroll itself (the fixed-height desktop panel).
  final ScrollController? scrollController;

  /// Whether the board draws its own title + star header. The desktop panel
  /// sets this false and renders the title/star in its own chrome.
  final bool showHeader;

  @override
  ConsumerState<StopBoard> createState() => _StopBoardState();
}

class _StopBoardState extends ConsumerState<StopBoard> with StopLiveRefresh {
  @override
  String get liveStopId => widget.stopId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final board = ref.watch(arrivalsProvider(widget.stopId));
    final stopLocation = ref
        .watch(stopLocationProvider(widget.stopId))
        .valueOrNull;

    final stopName =
        board.valueOrNull?.stopName ?? widget.initialStopName ?? '';

    final allAlerts =
        ref.watch(alertsProvider).valueOrNull ?? const <RouteAlert>[];
    final relevantAlerts = allAlerts.where((a) {
      if (a.isExpired) return false;
      final matchesLine = stopLocation?.lines.any(a.matchesLine) ?? false;
      return matchesLine || a.matchesStopName(stopName);
    }).toList();

    // Desktop island (no sheet controller): the board hugs its content, up to
    // the island's height, then scrolls inside (owner, 2026-11-25).
    final hug = widget.scrollController == null && !widget.showHeader;
    final content = <Widget>[
      RouteAlertsStrip(alerts: relevantAlerts),
      JamStopBanner(
        stopId: widget.stopId,
        lines: stopLocation?.lines ?? const [],
      ),
      board.when(
        loading: () =>
            EmptyState(icon: StizeIcons.transit, title: l10n.loadingArrivals),
        error: (err, _) => stopArrivalsErrorState(l10n, err, refreshStopNow),
        data: (b) => StopArrivalsList(
          stopId: widget.stopId,
          board: b,
          stopLines: stopLocation?.lines ?? const [],
          onRetry: refreshStopNow,
          onFocusVehicle: widget.onFocusVehicle,
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: hug ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (widget.showHeader) _header(theme, stopName),
        if (widget.showHeader) const Divider(height: 1),
        Flexible(
          fit: hug ? FlexFit.loose : FlexFit.tight,
          // One list on every platform (owner, 2026-11-26): the last card
          // stretches past the bottom and springs back, on the mobile sheet
          // and in the desktop island alike.
          child: StretchCardList(
            controller: widget.scrollController,
            shrinkWrap: hug,
            // Live data: pull to refresh, like Nearby (DS StretchList).
            onRefresh: () async {
              refreshStopNow();
              await ref.read(arrivalsProvider(widget.stopId).future);
            },
            children: content,
          ),
        ),
      ],
    );
  }

  Widget _header(ThemeData theme, String stopName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Row(
        children: [
          // Name, then the star status + More right after it; close stays on
          // the far right, away from More.
          Flexible(
            child: Text(
              stopName,
              style: StizeText.of(context).section,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          StopHeaderActions(stopId: widget.stopId, stopName: stopName),
          const Spacer(),
          if (widget.onClose != null)
            SheetCloseButton(onPressed: widget.onClose!),
        ],
      ),
    );
  }
}
