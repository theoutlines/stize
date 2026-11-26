import 'package:stize/core/design/stize_tokens.dart';
import 'package:flutter/material.dart';
import 'package:stize/core/design/stize_text.dart';

import 'follow_view.dart';
import 'level_header.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../l10n/app_localizations.dart';
import '../../core/design/stize_icons.dart';

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
    this.hug = false,
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

  /// Desktop: size to the content (a short empty state is a short card, a long
  /// list still grows to the full height and scrolls) instead of always
  /// stretching to the bottom of the screen.
  final bool hug;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PointerInterceptor(
      child: Material(
        elevation: 3,
        color: theme.colorScheme.surface,
        borderRadius: borderRadius,
        clipBehavior: borderRadius != null ? Clip.antiAlias : Clip.none,
        child: SizedBox(
          width: width,
          height: hug ? null : double.infinity,
          child: SafeArea(
            right: false,
            child: Column(
              mainAxisSize: hug ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (searchField != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                    child: searchField!,
                  ),
                // A LevelHeader owns its insets (one 16px left edge with the
                // content); other nav rows keep the panel's padding.
                if (navRow is LevelHeader || navRow is FollowHeader)
                  navRow!
                else if (navRow != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 8, 4),
                    child: navRow!,
                  ),
                Flexible(
                  fit: hug ? FlexFit.loose : FlexFit.tight,
                  // The lists stretch on a wheel or trackpad themselves
                  // (StretchCardList); the old whole-panel shift showed the
                  // island's background as a dark strip (owner, 2026-11-26).
                  child: child,
                ),
              ],
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
    return Row(
      children: [
        IconButton(
          icon: const Icon(StizeIcons.back),
          onPressed: onBack,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        ),
        ?leading,
        if (leading != null) const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: StizeText.of(context).label,
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
        borderRadius: BorderRadius.circular(StizeRadius.radiusPill),
        elevation: 4,
        child: InkWell(
          borderRadius: BorderRadius.circular(StizeRadius.radiusPill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (arrowTurns != null) ...[
                  Transform.rotate(
                    angle: arrowTurns! * 2 * 3.1415926,
                    child: Icon(
                      StizeIcons.nearMe,
                      size: 18,
                      color: theme.colorScheme.onInverseSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  l10n.backToVehicle,
                  style: StizeText.of(context).label.copyWith(
                    color: theme.colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w500,
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
