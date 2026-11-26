import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../core/design/stize_icons.dart';
import '../../../core/design/stize_text.dart';
import '../../../core/design/stize_tokens.dart';
import '../../../core/map_support.dart';
import '../../../domain/models/vehicle_type.dart';
import '../../../l10n/app_localizations.dart';
import '../sheet_chrome.dart';
import '../vehicle_icon.dart';

/// The compact bar at the bottom of the map while a line is focused (mobile,
/// line-only focus): the line badge in its transit colour, the route terminals
/// and a close button that leaves the focus.
///
/// It must show the instant follow starts, from any source, so [subtitle] may
/// be null until the route shape loads: then a neutral "Following" label keeps
/// the bar complete and exitable.
class FollowBar extends StatelessWidget {
  const FollowBar({
    super.key,
    required this.line,
    required this.type,
    required this.subtitle,
    required this.scheduled,
    required this.onClose,
  });

  final String line;
  final VehicleType type;

  /// "Origin → Destination" once the route shape is loaded.
  final String? subtitle;

  /// A schedule-predicted object: its position is a GTFS estimate, not a live
  /// fix, and the bar says so.
  final bool scheduled;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = StizeColors.of(context);
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: PointerInterceptor(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: StizeShadow.shadowMapControl,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: vehicleColor(type),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      vehicleGlyph(type, size: 16, color: colors.onTransit),
                      const SizedBox(width: 8),
                      Text(
                        line,
                        style: StizeType.lineNumber.copyWith(
                          color: colors.onTransit,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        subtitle ?? l10n.followingVehicle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: StizeText.of(context).body,
                      ),
                      if (scheduled)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              StizeIcons.clock,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                l10n.vehicleScheduled,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: StizeText.of(context).note.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                SheetCloseButton(onPressed: onClose),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
