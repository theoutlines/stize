import 'package:flutter/material.dart';

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
    builder: builder,
  );
}

/// The canonical drag handle: a 36×4 rounded pill in `outlineVariant`.
class SheetDragHandle extends StatelessWidget {
  const SheetDragHandle({super.key, this.bottom = 8});

  /// Bottom padding under the handle (sheets vary slightly: 8 for nearby, 4 when
  /// a header follows immediately).
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: 8, bottom: bottom),
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
}

/// The shared sheet corner radius (top corners rounded).
const BorderRadius kSheetRadius =
    BorderRadius.vertical(top: Radius.circular(20));

/// A `[← back] [title]` header row for an in-sheet subview, matching the sheets'
/// horizontal padding and title style. Back walks up the sheet's own view chain.
class SheetBackHeader extends StatelessWidget {
  const SheetBackHeader({super.key, required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
