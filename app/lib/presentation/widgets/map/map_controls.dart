import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../core/design/stize_icons.dart';
import '../../../core/design/stize_tokens.dart';
import '../../../l10n/app_localizations.dart';

/// Floating controls drawn over the home map. Each one is a plain widget: it
/// gets what it shows and a callback, and knows nothing about the map state.

/// A round floating map button (the menu burger on mobile).
class MapRoundButton extends StatelessWidget {
  const MapRoundButton({
    super.key,
    required this.icon,
    this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PointerInterceptor(
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 3,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(icon: Icon(icon), tooltip: tooltip, onPressed: onTap),
      ),
    );
  }
}

/// Zoom + / − stack. Shown only on desktop browsers (see the caller): on
/// phones pinch and double-tap handle zoom.
class MapZoomControl extends StatelessWidget {
  const MapZoomControl({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PointerInterceptor(
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 3,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(StizeIcons.plus), onPressed: onZoomIn),
            Divider(height: 1, thickness: 1, color: theme.dividerColor),
            IconButton(
              icon: const Icon(StizeIcons.minus),
              onPressed: onZoomOut,
            ),
          ],
        ),
      ),
    );
  }
}

/// The jam-mode toggle: a round button over the map, filled jam-amber while
/// [on]. It only nags (loud icon + red count badge) when [relevantCount] > 0,
/// i.e. a jam near the user, on the followed line or at the open stop; jams
/// elsewhere keep it present but quiet. Whether to show it at all is the
/// caller's call (no jams, no button).
class JamModeButton extends StatelessWidget {
  const JamModeButton({
    super.key,
    required this.on,
    required this.relevantCount,
    required this.onToggle,
  });

  final bool on;
  final int relevantCount;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = StizeColors.of(context);
    final loud = relevantCount > 0;
    final iconColor = on
        ? Colors.white
        : (loud
              ? colors.jam
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PointerInterceptor(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: on ? colors.jam : theme.colorScheme.surface,
              elevation: 3,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                // Round ink on a round button (the theme's icon-button shape
                // is a 12px square, which showed as a square inside the circle).
                style: IconButton.styleFrom(shape: const CircleBorder()),
                icon: Icon(StizeIcons.warning, color: iconColor),
                tooltip: AppLocalizations.of(context).jamModeTooltip,
                onPressed: onToggle,
              ),
            ),
            // Red count badge ONLY for context-relevant jams: a far-away jam
            // never lights it up.
            if (loud)
              Positioned(
                right: -2,
                top: -2,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    decoration: BoxDecoration(
                      color: colors.alertCount,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$relevantCount',
                      textAlign: TextAlign.center,
                      style: StizeType.control.copyWith(
                        color: Colors.white,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
