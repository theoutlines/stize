import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/context_slot.dart';
import '../../l10n/app_localizations.dart';

/// Header metadata shared by both context-slot shells (panel + sheet), so the
/// chrome (back-chip, title, leading pill, star, ×) is assembled in ONE place
/// and reads identically at either breakpoint.
class ContextSlotHeader {
  const ContextSlotHeader({
    required this.view,
    this.title,
    this.backLabel,
    this.onBack,
    this.leading,
    this.trailing,
    this.onClose,
  });

  final ContextView view;

  /// Main title (stop name / vehicle direction). Null for nearby.
  final String? title;

  /// Label of the parent one step up the chain ("Nearby", the stop name). When
  /// non-null a back-chip is shown; tapping it calls [onBack].
  final String? backLabel;
  final VoidCallback? onBack;

  /// A leading element before the title (e.g. the line pill in the vehicle view).
  final Widget? leading;

  /// A trailing action before the × (e.g. the favourite star in the stop view).
  final Widget? trailing;

  /// Close the slot (× → return to nearby). Null hides the × (nearby root).
  final VoidCallback? onClose;

  /// Whether the shell should draw its own title row. False when the hosted view
  /// renders its own header (e.g. [StopBoard] draws its name + star + ×), so the
  /// shell only supplies the back-chip above it.
  bool get hasTitleRow =>
      title != null || leading != null || trailing != null || onClose != null;
}

/// The back-chip pill ("‹ Nearby" / "‹ Batutova") — the single "up one step"
/// control the desktop panel uses in place of a sheet-dismiss gesture.
class ContextBackChip extends StatelessWidget {
  const ContextBackChip({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chevron_left,
                  size: 18, color: theme.colorScheme.primary),
              Text(
                label,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The title row (leading + title + trailing + ×), shared by both shells.
class ContextTitleRow extends StatelessWidget {
  const ContextTitleRow({super.key, required this.header});

  final ContextSlotHeader header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (header.leading != null) ...[
          header.leading!,
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            header.title ?? '',
            style: theme.textTheme.titleLarge,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (header.trailing != null) header.trailing!,
        if (header.onClose != null)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: header.onClose,
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          ),
      ],
    );
  }
}

/// The desktop persistent left panel (owner decision #1/#2/#4/#6). Always
/// present — nearby is its "closed" state, it never collapses to a full-width
/// map. A persistent search sits ABOVE every view; below it the back-chip and
/// title row, then the active view's content.
class ContextPanel extends StatelessWidget {
  const ContextPanel({
    super.key,
    required this.width,
    required this.header,
    required this.searchField,
    required this.child,
  });

  /// Resolved rubber-band width (see [panelWidthFor]).
  final double width;
  final ContextSlotHeader header;

  /// The persistent global search field (stops / streets / lines), shown in all
  /// three views. The host owns its state and results.
  final Widget searchField;

  /// The active view's content (NearbyList / StopBoard / VehicleView).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PointerInterceptor(
      child: Material(
        elevation: 3,
        color: theme.colorScheme.surface,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: SafeArea(
            right: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: searchField,
                ),
                if (header.backLabel != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ContextBackChip(
                      label: header.backLabel!,
                      onTap: header.onBack,
                    ),
                  ),
                if (header.hasTitleRow)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 8, 6),
                    child: ContextTitleRow(header: header),
                  ),
                const Divider(height: 1),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The mobile bottom-sheet shell (owner rule: unified detents peek/half/large,
/// mutual exclusion, a strip of map always on top). One persistent draggable
/// container swaps its content by [ContextView]; its size fraction is reported
/// up via [onSizeChanged] so the map's camera padding can follow the drag (the
/// visible-track contract).
class ContextSheet extends StatelessWidget {
  const ContextSheet({
    super.key,
    required this.controller,
    required this.header,
    required this.child,
    required this.onSizeChanged,
    this.showHandle = true,
  });

  final DraggableScrollableController controller;
  final ContextSlotHeader header;
  final Widget child;

  /// Called with the sheet's current height fraction (0..1) on every drag frame.
  final ValueChanged<double> onSizeChanged;
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        onSizeChanged(n.extent);
        return false;
      },
      child: DraggableScrollableSheet(
        controller: controller,
        initialChildSize: kDetentPeek,
        minChildSize: kDetentPeek,
        maxChildSize: kDetentLarge,
        snap: true,
        snapSizes: const [kDetentPeek, kDetentHalf, kDetentLarge],
        expand: false,
        builder: (context, scrollController) {
          return PointerInterceptor(
            child: Material(
              color: theme.colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              clipBehavior: Clip.antiAlias,
              elevation: 3,
              child: Column(
                children: [
                  if (showHandle) _handle(theme),
                  if (header.hasTitleRow)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 8, 4),
                      child: ContextTitleRow(header: header),
                    ),
                  Expanded(
                    // The active view scrolls with the sheet's controller so the
                    // drag-to-scroll hand-off works (drag the content up → the
                    // sheet grows, then the list scrolls).
                    child: PrimaryScrollController(
                      controller: scrollController,
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _handle(ThemeData theme) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// The floating "Back to vehicle" pill (owner decision #8) — shown ONLY while
/// follow is interrupted (a manual pan, or the vehicle left the viewport).
/// Recenters the camera on the vehicle and resumes follow; the label is the
/// l10n triple. An off-screen direction arrow hint sits beside it.
class BackToVehiclePill extends StatelessWidget {
  const BackToVehiclePill({
    super.key,
    required this.line,
    required this.onTap,
    this.arrowTurns,
  });

  final String line;
  final VoidCallback onTap;

  /// Direction hint toward the off-screen vehicle, in turns (0..1) for a
  /// [RotationTransition]-style arrow. Null hides the arrow.
  final double? arrowTurns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return PointerInterceptor(
      child: Material(
        color: theme.colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(999),
        elevation: 4,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (arrowTurns != null) ...[
                  Transform.rotate(
                    angle: arrowTurns! * 2 * 3.1415926,
                    child: Icon(Icons.navigation,
                        size: 18, color: theme.colorScheme.onInverseSurface),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  l10n.backToVehicle,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
