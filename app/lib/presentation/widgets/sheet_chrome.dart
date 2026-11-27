import 'package:flutter/material.dart';
import 'package:stize/core/design/stize_text.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../../core/context_slot.dart';
import '../../core/design/stize_icons.dart';
import '../../core/design/stize_tokens.dart';

/// Shared bottom-sheet chrome, so every mobile sheet (nearby / stop / vehicle /
/// the in-sheet fleet-card subview) uses ONE width + handle + surface treatment
/// instead of copy-pasted values (owner B#3 + acceptance #3: unify the sheets).
///
/// Detents live elsewhere (`kSheet*` in `core/context_slot.dart`) — this is only
/// the visual chrome.

/// Open a modal bottom sheet with the app's unified geometry: **full width**
/// (like the persistent nearby sheet — Material's default centres the sheet at
/// 640px on wider windows, which made the stop/vehicle sheets narrower than
/// nearby), scrollable, transparent background so the [builder] supplies its own
/// rounded [Material] via [kSheetRadius] + [SheetDragHandle].
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  Color? barrierColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: barrierColor,
    // Full width on every viewport (override Material's 640px max on wide ones).
    constraints: const BoxConstraints(maxWidth: double.infinity),
    builder: (ctx) => PointerInterceptor(child: (builder)(ctx)),
  );
}

/// The canonical drag handle: a 36×4 rounded pill in `outlineVariant`.
class SheetDragHandle extends StatelessWidget {
  const SheetDragHandle({super.key, this.bottom = 8, this.color});

  /// Bottom padding under the handle (sheets vary slightly: 8 for nearby, 4 when
  /// a header follows immediately).
  final double bottom;

  /// Override for a handle drawn on a coloured header (the follow card).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: bottom),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: color ?? theme.colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// The shared sheet corner radius (top corners rounded).
const BorderRadius kSheetRadius = BorderRadius.vertical(
  top: Radius.circular(24), // radius-hero: the top of the bottom sheet
);

/// A `[← back] [title]` header row for an in-sheet subview, matching the sheets'
/// horizontal padding and title style. Back walks up the sheet's own view chain.
class SheetBackHeader extends StatelessWidget {
  const SheetBackHeader({super.key, required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(StizeIcons.back),
            onPressed: onBack,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          Expanded(
            child: Text(
              title,
              style: StizeText.of(context).label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The one close button of a sheet level: a 32px circle in a 44px tap target.
/// Used inside a header row where the close lives in the panel (desktop
/// island, dialogs); on the mobile map the close rides above the sheet as a
/// [MapSheetCloseButton].
class SheetCloseButton extends StatelessWidget {
  const SheetCloseButton({
    super.key,
    required this.onPressed,
    this.background,
    this.color,
  });

  /// The tap target's side.
  static const double size = 44;

  /// Gap between the tap target's edge and the drawn circle (32 px). A close
  /// in a row shifts by it so the circle, not the target, lines up with the
  /// content edge below.
  static const double inset = (size - 32) / 2;

  final VoidCallback onPressed;
  final Color? background;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).closeButtonTooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: size / 2,
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: background ?? scheme.onSurface.withValues(alpha: 0.08),
              ),
              child: SizedBox.square(
                dimension: 32,
                child: Icon(
                  StizeIcons.close,
                  size: 18,
                  color: color ?? scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The close of the mobile sheet, outside it (owner, 2026-11-25): a 44px
/// round button over the map, just above the sheet's right edge, riding with
/// the sheet as it is dragged. Closing is a state of the sheet, so it never
/// sits on the map's own controls; the host pushes those up when the button
/// reaches them, the same way the search pill does.
class MapSheetCloseButton extends StatelessWidget {
  const MapSheetCloseButton({super.key, required this.onPressed});

  static const double size = 44;

  /// Gap between the button and the sheet's top edge.
  static const double gap = 12;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PointerInterceptor(
      child: Semantics(
        button: true,
        label: MaterialLocalizations.of(context).closeButtonTooltip,
        child: Material(
          color: theme.colorScheme.surface,
          elevation: 3,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox.square(
              dimension: size,
              child: Icon(
                StizeIcons.close,
                size: 18,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The frame of a modal map sheet (design system: MapSheet): the unified
/// detents (peek, half, large; large is never fullscreen, a map strip always
/// stays on top), a surface with the sheet radius, the grabber, then
/// [childBuilder]'s widgets in a column. The stop sheet and the vehicle sheet
/// both draw THIS, so their chrome can't drift apart. It carries the same
/// `shadow-sheet` as the persistent Nearby sheet.
///
/// The surface is a [Material] (not a plain coloured box) so rows paint their
/// ink splashes on it; [PointerInterceptor] stops taps on the sheet from
/// falling through to the MapLibre view underneath on web (no-op on mobile).
class MapSheetFrame extends StatelessWidget {
  const MapSheetFrame({
    super.key,
    required this.childBuilder,
    this.initialSize,
  });

  /// Opening height as a share of the screen; null = the half detent.
  final double? initialSize;

  /// The sheet's content under the grabber; gets the sheet's scroll controller.
  final List<Widget> Function(
    BuildContext context,
    ScrollController scrollController,
  )
  childBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: (initialSize ?? kSheetHalf).clamp(
        kSheetPeek,
        kSheetLarge,
      ),
      minChildSize: kSheetPeek,
      maxChildSize: kSheetLarge,
      snap: true,
      snapSizes: const [kSheetPeek, kSheetHalf, kSheetLarge],
      expand: false,
      builder: (context, scrollController) => PointerInterceptor(
        // The system sheet shadow (design system: MapSheet, `shadow-sheet`),
        // the same as the Nearby sheet.
        child: DecoratedBox(
          decoration: const BoxDecoration(
            borderRadius: kSheetRadius,
            boxShadow: StizeShadow.shadowSheet,
          ),
          child: Material(
            color: theme.colorScheme.surface,
            borderRadius: kSheetRadius,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                const SheetDragHandle(bottom: 4),
                ...childBuilder(context, scrollController),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
