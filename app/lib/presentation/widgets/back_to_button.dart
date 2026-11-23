import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../../core/design/stize_icons.dart';

/// Leading back control for screens pushed over the map (My stops, Settings).
/// While a stop is open on the map underneath it reads "← Slavija", so the user
/// sees the stop is still there and that back returns to it; otherwise it's a
/// plain back arrow.
class BackToButton extends ConsumerWidget {
  const BackToButton({super.key});

  /// Width to give the AppBar's leading slot so the label fits.
  static const double leadingWidth = 180;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(openStopNameProvider);
    if (name == null || name.isEmpty) {
      return const Align(alignment: Alignment.centerLeft, child: BackButton());
    }
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(StizeIcons.back),
          label: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurface,
            textStyle: theme.textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }
}
