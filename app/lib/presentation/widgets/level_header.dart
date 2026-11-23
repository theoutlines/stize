import 'package:flutter/material.dart';

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasBack)
            TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text(
                backLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
            ),
          Row(
            children: [
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              ?trailing,
              const Spacer(),
              if (!hasBack && onClose != null)
                IconButton(
                  onPressed: onClose,
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                  ),
                  icon: const Icon(Icons.close, size: 20),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
