import 'package:flutter/material.dart';
import 'package:stize/core/design/stize_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/external_link.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../../core/design/stize_icons.dart';
import '../../core/design/stize_tokens.dart';

/// Gap between the round menu button and the top-left screen edge (matches the
/// map's floating controls: SafeArea + 12).
const double kMenuButtonInset = 12;

/// Diameter of the round map buttons (an IconButton in a circular Material).
const double kMenuButtonSize = 48;

/// Opens the app menu: a popover anchored under the round menu button, over
/// whatever is on screen (the map, or a stop sheet on it). Destinations push
/// over the map, so the map and any open stop stay exactly as they were
/// underneath; back returns to them.
///
/// [topInset] is the status-bar inset of the screen the button sits on; pass
/// it from a context that still has it (a modal sheet's context may not).
Future<void> showAppMenu(
  BuildContext context, {
  required double topInset,
  required int currentIndex,
  required ValueChanged<int> onSelectSection,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    // DS `scrim`: behind a modal.
    barrierColor: StizeColors.of(context).scrim,
    transitionDuration: StizeMotion.fast,
    pageBuilder: (menuContext, _, _) => PointerInterceptor(
      child: AppMenuOverlay(
        topInset: topInset,
        currentIndex: currentIndex,
        onSelectSection: onSelectSection,
      ),
    ),
    transitionBuilder: (_, animation, _, child) {
      // Opens on fast (250), closes on quick (150): the reverse curve is done
      // in the first 60% of the run.
      final curved = CurvedAnimation(
        parent: animation,
        curve: StizeMotion.smoothOut,
        reverseCurve: StizeMotion.closeQuick,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          alignment: Alignment.topLeft,
          scale: Tween<double>(
            begin: StizeMotion.scaleDropdown,
            end: 1,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// The menu's full-screen layer: a close button exactly over the menu button,
/// and the popover card under it. Public for widget tests.
class AppMenuOverlay extends StatelessWidget {
  const AppMenuOverlay({
    super.key,
    required this.topInset,
    required this.currentIndex,
    required this.onSelectSection,
  });

  final double topInset;
  final int currentIndex;
  final ValueChanged<int> onSelectSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final top = topInset + kMenuButtonInset;
    return Stack(
      children: [
        // A tap anywhere outside the card closes the menu (owner, 2026-11-23).
        // The pointer interceptor around the overlay swallows taps before the
        // route's barrier sees them, so the overlay dismisses itself.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        Positioned(
          left: kMenuButtonInset,
          top: top,
          child: Material(
            color: theme.colorScheme.onSurface,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              icon: Icon(StizeIcons.close, color: theme.colorScheme.surface),
              tooltip: l10n.menuClose,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        Positioned(
          left: kMenuButtonInset,
          top: top + kMenuButtonSize + 8,
          width: 264,
          child: AppMenuCard(
            currentIndex: currentIndex,
            onSelectSection: onSelectSection,
          ),
        ),
      ],
    );
  }
}

/// The popover card: primary destinations, then the quieter contact/legal rows.
class AppMenuCard extends ConsumerWidget {
  const AppMenuCard({
    super.key,
    required this.currentIndex,
    required this.onSelectSection,
  });

  /// 0 = map, 1 = coverage (only while its flag is on).
  final int currentIndex;
  final ValueChanged<int> onSelectSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final coverage = ref.watch(coverageEnabledProvider);
    final analytics = ref.watch(analyticsEnabledProvider);
    final donateUrl = ref.watch(donateUrlProvider);

    // Close the menu first, then act from the page underneath (the root
    // navigator), so destinations stack over the map, not over the menu.
    void go(void Function(NavigatorState nav, GoRouter router) action) {
      final nav = Navigator.of(context, rootNavigator: true);
      final router = GoRouter.of(context);
      nav.pop();
      action(nav, router);
    }

    final rows = <Widget>[
      if (coverage)
        _MenuRow(
          icon: currentIndex == 1 ? StizeIcons.map : StizeIcons.hub,
          label: currentIndex == 1 ? l10n.navHome : l10n.navCoverage,
          onTap: () {
            Navigator.of(context).pop();
            onSelectSection(currentIndex == 1 ? 0 : 1);
          },
        ),
      _MenuRow(
        icon: StizeIcons.star,
        label: l10n.navMyStops,
        // A level in the map's sheet / panel, not a separate screen.
        onTap: () {
          Navigator.of(context).pop();
          ref.read(myStopsRequestProvider.notifier).state++;
        },
      ),
      _MenuRow(
        icon: StizeIcons.compass,
        label: l10n.guideTitle,
        onTap: () {
          Navigator.of(context).pop();
          ref.read(guideRequestProvider.notifier).state++;
        },
      ),
      if (analytics)
        _MenuRow(
          icon: StizeIcons.stats,
          label: l10n.cityTitle,
          onTap: () => go((_, router) => router.push('/analytics')),
        ),
      // A compact sheet over the current screen, not a full page: two controls
      // don't warrant one, and the map and any open stop stay put.
      _MenuRow(
        icon: StizeIcons.settings,
        label: l10n.settingsTitle,
        onTap: () {
          Navigator.of(context).pop();
          ref.read(settingsRequestProvider.notifier).state++;
        },
      ),
    ];

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...rows,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            _MenuRow(
              icon: StizeIcons.chat,
              label: l10n.drawerShareFeedback,
              small: true,
              onTap: () {
                Navigator.of(context).pop();
                ref.read(feedbackRequestProvider.notifier).state++;
              },
            ),
            if (donateUrl != null)
              _MenuRow(
                icon: StizeIcons.heart,
                label: l10n.menuSupport,
                small: true,
                // Synchronous launch inside the tap keeps the browser's
                // user-activation window (see openExternalUrl).
                onTap: () {
                  openExternalUrl(donateUrl);
                  Navigator.of(context).pop();
                },
              ),
            // One full-height row (not three small adjacent links, which were
            // too easy to mis-tap); licences and privacy live inside About.
            _MenuRow(
              icon: StizeIcons.info,
              label: l10n.aboutTitle,
              small: true,
              onTap: () => go((_, router) => router.push('/about')),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.small = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = small
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        height: small ? 44 : 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, size: small ? 20 : 22, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StizeText.of(context).body.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
