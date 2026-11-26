import 'package:flutter/material.dart';
import 'package:stize/core/design/stize_text.dart';
import '../../core/design/stize_icons.dart';
import 'sheet_chrome.dart';

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
  /// On the mobile map the host passes no [onClose]: the close rides above the
  /// sheet instead ([MapSheetCloseButton]).
  final String? backLabel;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  /// Optional action after the title (the favourite star on a stop).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hasBack = backLabel != null && onBack != null;
    // One left edge for everything in a level (owner, 2026-11-23): back
    // link, title, the board's update time, chips and cards all start 16px in.
    return Padding(
      // Right: 10 + the 44px tap box's 6px inset puts the 32px close circle on
      // the same 16px edge as the cards below.
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasBack) _BackLink(label: backLabel!, onTap: onBack!),
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
                        // Screen title per the system: h1 (28/32, 500).
                        style: StizeText.of(context).h1,
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
              if (!hasBack && onClose != null)
                SheetCloseButton(onPressed: onClose!),
            ],
          ),
        ],
      ),
    );
  }
}

/// "← previous level": a plain text link. No box on hover or press (a tight
/// box clipped the arrow, owner 2026-11-25): the words brighten instead.
class _BackLink extends StatefulWidget {
  const _BackLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_BackLink> createState() => _BackLinkState();
}

class _BackLinkState extends State<_BackLink> {
  bool _on = false;

  void _set(bool v) {
    if (v != _on) setState(() => _on = v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _on ? scheme.onSurface : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _set(true),
        onExit: (_) => _set(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _set(true),
          onTapCancel: () => _set(false),
          onTapUp: (_) => _set(false),
          onTap: widget.onTap,
          child: SizedBox(
            height: 36,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(StizeIcons.back, size: 18, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StizeText.of(context).body.copyWith(color: color),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
