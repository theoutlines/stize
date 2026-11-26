import 'package:flutter/material.dart';

import '../../core/design/stize_icons.dart';
import '../../core/design/stize_text.dart';
import '../../core/design/stize_tokens.dart';
import 'flat_cards.dart';

/// DS Banner: one notice at the top of a list (a jam on a line, a GSP route
/// alert). The same form as the GuideStrip (owner, 2026-11-26): it opens the
/// list and scrolls with it. Mobile: flat, edge to edge, a hairline under it;
/// desktop island: rounded like the island's cards. Tapping toggles [details]
/// in place.
class NoticeStrip extends StatelessWidget {
  const NoticeStrip({
    super.key,
    required this.icon,
    required this.title,
    required this.surface,
    this.foreground,
    this.body,
    this.details,
    this.open = false,
    this.onTap,
  });

  final IconData icon;
  final String title;

  /// The strip's fill: `jam` at 13% (20% confirmed), `fill-08` for a notice,
  /// `fill-14` for an active disruption.
  final Color surface;

  /// Title and icon colour; `ink` by default.
  final Color? foreground;

  /// Always shown under the title (a lone alert's text).
  final Widget? body;

  /// Shown under the title while [open]; a chevron says it can open.
  final Widget? details;
  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final flat = FlatCards.of(context);
    final c = StizeColors.of(context);
    final text = StizeText.of(context);
    final fg = foreground ?? c.ink;
    return Material(
      color: surface,
      shape: flat
          ? Border(bottom: BorderSide(color: c.stripeLine))
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(StizeRadius.radiusCard),
            ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            StizeSpace.space4,
            StizeSpace.space3,
            StizeSpace.space2,
            StizeSpace.space3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  top: 2,
                  right: StizeSpace.space3,
                ),
                child: Icon(icon, size: 20, color: fg),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.label.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (body != null) ...[
                      const SizedBox(height: StizeSpace.space1),
                      body!,
                    ],
                    if (open && details != null) ...[
                      const SizedBox(height: StizeSpace.space2),
                      details!,
                    ],
                  ],
                ),
              ),
              if (details != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: StizeSpace.space2,
                    vertical: 2,
                  ),
                  child: Icon(
                    open ? StizeIcons.chevronUp : StizeIcons.chevronDown,
                    size: 20,
                    color: c.ink50,
                  ),
                )
              else
                const SizedBox(width: StizeSpace.space2),
            ],
          ),
        ),
      ),
    );
  }
}
