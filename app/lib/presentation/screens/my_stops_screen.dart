import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/back_to_button.dart';
import '../widgets/empty_state.dart';

class MyStopsScreen extends ConsumerWidget {
  const MyStopsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final favorites = ref.watch(favoritesControllerProvider);
    final customNames =
        ref.watch(customNamesControllerProvider).valueOrNull ??
        const <String, String>{};

    return Scaffold(
      appBar: AppBar(
        leading: const BackToButton(),
        leadingWidth: BackToButton.leadingWidth,
        title: Text(l10n.navMyStops),
      ),
      body: favorites.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (err, st) => EmptyState(icon: Icons.error_outline, title: err.toString()),
        data: (stops) {
          if (stops.isEmpty) {
            return EmptyState(
              icon: Icons.star_outline,
              title: l10n.myStopsEmptyTitle,
              subtitle: l10n.myStopsEmptySubtitle,
            );
          }
          return ListView.builder(
            itemCount: stops.length,
            itemBuilder: (context, i) {
              final stop = stops[i];
              final custom = customNames['stop:${stop.stopId}'];
              return ListTile(
                leading: const Icon(Icons.star),
                title: Text(custom ?? stop.name),
                subtitle: custom != null ? Text(stop.name) : null,
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.removeFromFavorites,
                  onPressed: () => ref.read(favoritesControllerProvider.notifier).remove(stop.stopId),
                ),
                // Open on the map's own sheet (the map flies there), not a
                // separate stop screen — the stop that was open stays one tap
                // away via "Back to …".
                // Pop first, then request: the map swaps its sheet only once
                // this screen is off the top of the stack.
                onTap: () {
                  final request = ref.read(stopOpenRequestProvider.notifier);
                  Navigator.of(context).pop();
                  request.state =
                      (stopId: stop.stopId, stopName: custom ?? stop.name);
                },
              );
            },
          );
        },
      ),
    );
  }
}
