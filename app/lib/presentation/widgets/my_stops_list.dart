import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'empty_state.dart';
import '../../core/design/stize_icons.dart';
import '../../core/design/stize_tokens.dart';

/// The saved stops, as a level inside the context slot (mobile sheet / desktop
/// panel). Tapping a stop opens it as the next level on the same map.
class MyStopsList extends ConsumerWidget {
  const MyStopsList({
    super.key,
    required this.onTapStop,
    this.scrollController,
  });

  final void Function(String stopId, String stopName) onTapStop;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final favorites = ref.watch(favoritesControllerProvider);
    final customNames =
        ref.watch(customNamesControllerProvider).valueOrNull ??
        const <String, String>{};
    return favorites.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (err, st) =>
          EmptyState(icon: StizeIcons.error, title: err.toString()),
      data: (stops) {
        if (stops.isEmpty) {
          return ListView(
            controller: scrollController,
            shrinkWrap: scrollController == null,
            children: [
              EmptyState(
                icon: StizeIcons.star,
                title: l10n.myStopsEmptyTitle,
                subtitle: l10n.myStopsEmptySubtitle,
              ),
            ],
          );
        }
        return ListView.separated(
          controller: scrollController,
          shrinkWrap: scrollController == null,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          itemCount: stops.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final stop = stops[i];
            final custom = customNames['stop:${stop.stopId}'];
            final name = custom ?? stop.name;
            return Material(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                minTileHeight: 56,
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: custom != null ? Text(stop.name) : null,
                // A filled star, not a ×: a × reads as "close" everywhere else
                // (owner, 2026-11-25). Tapping it takes the stop out.
                trailing: IconButton(
                  icon: Icon(
                    StizeIcons.starFilled,
                    size: 20,
                    color: StizeColors.of(context).favorite,
                  ),
                  tooltip: l10n.removeFromFavorites,
                  onPressed: () => ref
                      .read(favoritesControllerProvider.notifier)
                      .remove(stop.stopId),
                ),
                onTap: () => onTapStop(stop.stopId, name),
              ),
            );
          },
        );
      },
    );
  }
}
