import 'package:flutter/material.dart';
import '../../core/design/stize_icons.dart';

/// Header of a level in the context slot (mobile sheet / desktop panel).
///
/// One control per level (owner, 2026-11-23): when there is a previous level a
/// "← `previous`" back link sits above the title and walks one step back; on the
/// first level there is nowhere to go back to, so a close button (×) sits next
/// to the title instead and returns to Nearby.
class LevelHeader extends StatelessWidget {
  const LevelHeader({
    super.key,
    required this.title,
    this.backLabel,
    this.onBack,
    this.onClose,
    this.trailing,
  });

  final String title;

  /// Name of the previous level; null on the first level (then [onClose] shows).
  final String? backLabel;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  /// Optional action after the title (the favourite star on a stop).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasBack = backLabel != null && onBack != null;
    // One left edge for everything in a level (owner, 2026-11-23): back
    // link, title, the board's update time, chips and cards all start 16px in.
    return Padding(
      // Right: 10 + the 44px tap box's 6px inset puts the 32px close circle on
      // the same 16px edge as the cards below.
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasBack)
            // A plain text link, no pill: arrow + previous level's name.
            Semantics(
              button: true,
              child: InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 36,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        StizeIcons.back,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          backLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ),
          Row(
            children: [
              // Title + star take all the room up to the close button (a
              // Flexible + Spacer pair split it in half and cut long names).
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
              if (!hasBack && onClose != null)
                // Compact round close: a 32px circle on the title's centre
                // line (the old 48px filled square sat off the baseline),
                // inside a 44px tap target.
                Semantics(
                  button: true,
                  label: MaterialLocalizations.of(context).closeButtonTooltip,
                  child: InkResponse(
                    onTap: onClose,
                    radius: 22,
                    child: SizedBox.square(
                      dimension: 44,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scheme.onSurface.withValues(alpha: 0.08),
                          ),
                          child: SizedBox.square(
                            dimension: 32,
                            child: Icon(
                              StizeIcons.close,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
