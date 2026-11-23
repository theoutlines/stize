import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/external_link.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../screens/settings_screen.dart';
import 'drawer_footer.dart';

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
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (menuContext, _, _) => PointerInterceptor(
      child: AppMenuOverlay(
        topInset: topInset,
        currentIndex: currentIndex,
        onSelectSection: onSelectSection,
      ),
    ),
    transitionBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          alignment: Alignment.topLeft,
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
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
        Positioned(
          left: kMenuButtonInset,
          top: top,
          child: Material(
            color: theme.colorScheme.onSurface,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              icon: Icon(Icons.close, color: theme.colorScheme.surface),
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
          icon: currentIndex == 1 ? Icons.map_outlined : Icons.hub_outlined,
          label: currentIndex == 1 ? l10n.navHome : l10n.navCoverage,
          onTap: () {
            Navigator.of(context).pop();
            onSelectSection(currentIndex == 1 ? 0 : 1);
          },
        ),
      _MenuRow(
        icon: Icons.star_outline,
        label: l10n.navMyStops,
        // A level in the map's sheet / panel, not a separate screen.
        onTap: () {
          Navigator.of(context).pop();
          ref.read(myStopsRequestProvider.notifier).state++;
        },
      ),
      if (analytics)
        _MenuRow(
          icon: Icons.query_stats_outlined,
          label: 'Аналитика',
          onTap: () => go((_, router) => router.push('/analytics')),
        ),
      // A compact sheet over the current screen, not a full page: two controls
      // don't warrant one, and the map and any open stop stay put.
      _MenuRow(
        icon: Icons.settings_outlined,
        label: l10n.settingsTitle,
        onTap: () {
          final host = Navigator.of(context, rootNavigator: true).context;
          Navigator.of(context).pop();
          showSettingsSheet(host);
        },
      ),
    ];

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(22),
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
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Divider(height: 1, color: theme.colorScheme.outlineVariant),
            ),
            _MenuRow(
              icon: Icons.chat_bubble_outline,
              label: l10n.drawerShareFeedback,
              small: true,
              onTap: () {
                final host = Navigator.of(context, rootNavigator: true).context;
                Navigator.of(context).pop();
                showFeedbackSheet(host);
              },
            ),
            if (donateUrl != null)
              _MenuRow(
                icon: Icons.favorite_border,
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
              icon: Icons.info_outline,
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
    final color = small ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        height: small ? 44 : 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(icon, size: small ? 20 : 22, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (small ? theme.textTheme.bodyMedium : theme.textTheme.bodyLarge)
                      ?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
