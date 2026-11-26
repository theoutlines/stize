import 'package:flutter/material.dart';

/// The staging-only diagnostics box over the map (`isStaging`, never in prod):
/// white monospace lines on a dark card, bottom-right, out of the way of the
/// panel, the search and the top-right controls (owner, 2026-11-23). It ignores
/// pointers, so it never blocks the map under it.
///
/// On Flutter-CanvasKit the map and its layers aren't in the DOM, so this box
/// is the one reliable window into the render pipeline. Keep it.
class DiagnosticsOverlay extends StatelessWidget {
  const DiagnosticsOverlay({
    super.key,
    required this.lines,
    required this.bottomMargin,
  });

  final List<String> lines;

  /// Clearance from the bottom: above the mobile sheet, or a plain margin
  /// next to the desktop panel.
  final double bottomMargin;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: IgnorePointer(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            margin: EdgeInsets.only(right: 12, bottom: bottomMargin),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final line in lines)
                  Text(
                    line,
                    // ds-ok: staging-only diagnostics overlay.
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.35,
                      fontFamily: 'monospace',
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
