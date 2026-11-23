import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/design/stize_icons.dart';
import '../../core/design/stize_tokens.dart';
import '../../l10n/app_localizations.dart';

/// The one-scroll home's search pill (owner, 2026-11-23). It always sits on the
/// map, never on a backing: [locate | where the list is | search].
///
/// Tapping it activates search in place: the locate segment slides out to the
/// left, the field grows across the pill and the magnifier turns into a close
/// cross (clear and leave). Results replace the cards in the list below.
class MapSearchPill extends StatelessWidget {
  const MapSearchPill({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.active,
    required this.placeLabel,
    required this.onLocate,
    required this.onActivate,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool active;

  /// Where the list is, e.g. the nearest stop. Null shows only "Nearby".
  final String? placeLabel;
  final VoidCallback onLocate;
  final VoidCallback onActivate;
  final VoidCallback onClose;

  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final c = StizeColors.of(context);
    final l10n = AppLocalizations.of(context);
    const seg = height;
    // The shadow sits OUTSIDE the clipped surface: inside the clip it painted
    // a grey haze over the pill (owner, 2026-11-23: the light pill was grey).
    return PointerInterceptor(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(StizeRadius.radiusButton),
          boxShadow: StizeShadow.shadowMapControl,
        ),
        child: Material(
          color: c.sheet,
          elevation: 0,
          borderRadius: BorderRadius.circular(StizeRadius.radiusButton),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                // Locate: slides out to the left while searching.
                AnimatedContainer(
                  duration: StizeMotion.fast,
                  curve: StizeMotion.smoothOut,
                  width: active ? 0 : seg + 1,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerRight,
                      minWidth: seg + 1,
                      maxWidth: seg + 1,
                      child: Row(
                        children: [
                          SizedBox(
                            width: seg,
                            height: seg,
                            child: IconButton(
                              tooltip: l10n.locateMeTooltip,
                              style: IconButton.styleFrom(
                                shape: const RoundedRectangleBorder(),
                              ),
                              icon: Icon(
                                StizeIcons.locate,
                                color: c.ink,
                                size: 22,
                              ),
                              onPressed: onLocate,
                            ),
                          ),
                          Container(width: 1, height: 28, color: c.line),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  // The field is always mounted so a tap lands on a real input:
                  // iOS only opens the keyboard when focus comes from the tap
                  // itself (owner, 2026-11-23: the first tap opened nothing).
                  // Fill the pill's height; both layers centre on it (owner,
                  // iPhone: the hint rode high in the field).
                  child: Stack(
                    fit: StackFit.expand,
                    alignment: Alignment.centerLeft,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: StizeSpace.space3,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextField(
                            controller: controller,
                            focusNode: focusNode,
                            onTap: active ? null : onActivate,
                            textInputAction: TextInputAction.search,
                            textAlignVertical: TextAlignVertical.center,
                            style: StizeType.body.copyWith(
                              color: active ? c.ink : Colors.transparent,
                            ),
                            cursorColor: active ? c.ink : Colors.transparent,
                            decoration: InputDecoration(
                              hintText: active ? l10n.searchHint : null,
                              hintStyle: StizeType.body.copyWith(
                                color: c.ink50,
                              ),
                              filled: false,
                              isCollapsed: true,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ),
                      if (!active)
                        IgnorePointer(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: StizeSpace.space3,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.contextNearbyTitle,
                                    style: StizeType.caption.copyWith(
                                      color: c.ink60,
                                    ),
                                  ),
                                  Text(
                                    placeLabel ?? l10n.searchHint,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: StizeType.body.copyWith(
                                      color: placeLabel == null
                                          ? c.ink50
                                          : c.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  width: seg,
                  height: seg,
                  child: IconButton(
                    tooltip: active
                        ? MaterialLocalizations.of(context).closeButtonTooltip
                        : MaterialLocalizations.of(context).searchFieldLabel,
                    style: IconButton.styleFrom(
                      shape: const RoundedRectangleBorder(),
                    ),
                    onPressed: active
                        ? onClose
                        : () {
                            // Focus inside the tap so iOS opens the keyboard.
                            focusNode.requestFocus();
                            onActivate();
                          },
                    icon: AnimatedSwitcher(
                      duration: StizeMotion.quick,
                      switchInCurve: StizeMotion.inOut,
                      switchOutCurve: StizeMotion.inOut,
                      child: Icon(
                        active ? StizeIcons.close : StizeIcons.search,
                        key: ValueKey(active),
                        size: active ? 20 : 22,
                        color: active ? c.ink60 : c.ink,
                      ),
                    ),
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
