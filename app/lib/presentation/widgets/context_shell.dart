import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../l10n/app_localizations.dart';

/// The desktop persistent left panel (owner decision #1/#2/#4/#6) — a
/// DESKTOP-ONLY surface: on the mobile breakpoint the app keeps today's
/// independent sheets, and none of this code runs (owner R1 #1).
///
/// Layout (owner R1 #4 — no header matryoshka): a persistent search row on top
/// (all views), then, for the context views only, ONE navigation row
/// `[← back] [title]` (no ×, no separate back-chip — back IS the exit up the
/// chain), then the active view's content. The hamburger lives in the search
/// row and only on the nearby (root) view.
class ContextPanel extends StatelessWidget {
  const ContextPanel({
    super.key,
    required this.width,
    required this.searchField,
    required this.child,
    this.navRow,
    this.borderRadius,
  });

  /// Resolved rubber-band width (see `panelWidthFor`).
  final double width;

  /// Rounded corners when the panel is a floating "island" (Google-Maps look).
  /// Null = square (legacy flush-to-edge).
  final BorderRadius? borderRadius;

  /// The persistent global search row (search field, plus the hamburger on the
  /// nearby view). Shown in all views. Null when the host renders the global
  /// search as a separate persistent element above the panel (so it survives the
  /// desktop collapse) — the panel then omits its own search row.
  final Widget? searchField;

  /// The single `[← back] [title]` nav row for a context view; null on nearby.
  final Widget? navRow;

  /// The active view's content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A header (search / nav row) gets a divider under it; the plain nearby
    // island has neither, so it shows NO top divider — the first card starts
    // immediately (owner acceptance #1b).
    final hasHeader = searchField != null || navRow != null;
    return PointerInterceptor(
      child: Material(
        elevation: 3,
        color: theme.colorScheme.surface,
        borderRadius: borderRadius,
        clipBehavior: borderRadius != null ? Clip.antiAlias : Clip.none,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: SafeArea(
            right: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (searchField != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 12, 6),
                    child: searchField!,
                  ),
                if (navRow != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 8, 4),
                    child: navRow!,
                  ),
                if (hasHeader) const Divider(height: 1),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Google-Maps-style collapse control: a small vertically-centred tab docked
/// to the panel's right edge. Tapping it hides the panel (the caller slides it
/// off and drops the left map inset to zero) and flips the chevron; tapping again
/// restores it. Styled to the app's surface theme (not a raw Material button).
///
/// Purely presentational — [collapsed] drives the chevron direction and [onTap]
/// toggles. The host positions it (right edge when open, screen edge when
/// collapsed) and animates the move.
class PanelCollapseTab extends StatelessWidget {
  const PanelCollapseTab({
    super.key,
    required this.collapsed,
    required this.onTap,
    this.tooltip,
  });

  final bool collapsed;
  final VoidCallback onTap;
  final String? tooltip;

  static const double width = 22;
  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Rounded on the OUTER (right) side only, so it reads as a tab growing out of
    // the panel's edge — same idea in both states (the panel edge, or the screen
    // edge once collapsed).
    const radius = BorderRadius.only(
      topRight: Radius.circular(8),
      bottomRight: Radius.circular(8),
    );
    return PointerInterceptor(
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 3,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Tooltip(
            message: tooltip ?? '',
            child: SizedBox(
              width: width,
              height: height,
              child: Icon(
                collapsed ? Icons.chevron_right : Icons.chevron_left,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The single `[← back] [title]` navigation row inside a context view (stop /
/// vehicle / model). Back walks up the chain — there is no separate close.
class ContextNavRow extends StatelessWidget {
  const ContextNavRow({
    super.key,
    required this.onBack,
    required this.title,
    this.leading,
    this.trailing,
  });

  final VoidCallback onBack;

  /// The current view's title (stop name / direction / model name).
  final String title;

  /// Optional element between the back arrow and the title (e.g. the line pill).
  final Widget? leading;

  /// Optional trailing action (e.g. the favourite star on a stop).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        ),
        ?leading,
        if (leading != null) const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ?trailing,
      ],
    );
  }
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

  /// Direction hint toward the off-screen vehicle, in turns (0..1). Null hides
  /// the arrow.
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
