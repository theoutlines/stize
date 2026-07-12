import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/adaptive.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../screens/my_stops_screen.dart';

/// The app's primary navigation, moved from a bottom tab bar into a left
/// drawer. Nav items sit at the top (and scroll if the list ever grows); the
/// About block stays pinned to the bottom via an [Expanded] spacer.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  /// 0 = Map, 1 = Ideas, 2 = Coverage (when its flag is on). Settings and About
  /// are not indexed pages.
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    void select(int index) {
      Navigator.of(context).pop(); // close the drawer
      onSelect(index);
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.directions_transit_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(l10n.appTitle, style: theme.textTheme.titleLarge),
                ],
              ),
            ),
            const Divider(height: 1),
            // Nav items — scroll if they ever outgrow the space, keeping About
            // pinned to the bottom.
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _NavTile(
                    icon: Icons.map_outlined,
                    selectedIcon: Icons.map,
                    label: l10n.navHome,
                    selected: currentIndex == 0,
                    onTap: () => select(0),
                  ),
                  _NavTile(
                    icon: Icons.lightbulb_outline,
                    selectedIcon: Icons.lightbulb,
                    label: l10n.navIdeas,
                    selected: currentIndex == 1,
                    onTap: () => select(1),
                  ),
                  // Coverage map (infographic) — shown only when the remote
                  // `coverage_map_show` flag is on. It's the third IndexedStack
                  // section (index 2), which only exists while the flag is on.
                  Consumer(
                    builder: (context, ref, _) {
                      if (!ref.watch(coverageEnabledProvider)) {
                        return const SizedBox.shrink();
                      }
                      return _NavTile(
                        icon: Icons.hub_outlined,
                        selectedIcon: Icons.hub,
                        label: l10n.navCoverage,
                        selected: currentIndex == 2,
                        onTap: () => select(2),
                      );
                    },
                  ),
                  _NavTile(
                    icon: Icons.star_outline,
                    selectedIcon: Icons.star,
                    label: l10n.navMyStops,
                    selected: false,
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        adaptiveRoute((_) => const MyStopsScreen()),
                      );
                    },
                  ),
                  // Draft transport-analytics — shown only when the remote
                  // `analytics_show` flag is on (hidden from users otherwise).
                  Consumer(
                    builder: (context, ref, _) {
                      if (!ref.watch(analyticsEnabledProvider)) {
                        return const SizedBox.shrink();
                      }
                      return _NavTile(
                        icon: Icons.query_stats_outlined,
                        selectedIcon: Icons.query_stats,
                        label: 'Аналитика',
                        selected: false,
                        onTap: () {
                          Navigator.of(context).pop();
                          context.push('/analytics');
                        },
                      );
                    },
                  ),
                  _NavTile(
                    icon: Icons.settings_outlined,
                    selectedIcon: Icons.settings,
                    label: l10n.settingsTitle,
                    selected: false,
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push('/settings');
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // About block, pinned to the bottom of the drawer.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.aboutTitle, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    l10n.aboutDescription,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.aboutDisclaimer,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListTile(
        selected: selected,
        leading: Icon(selected ? selectedIcon : icon),
        title: Text(label),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
        selectedColor: Theme.of(context).colorScheme.onSecondaryContainer,
        onTap: onTap,
      ),
    );
  }
}
